# DualShock motion and touchpad

Branch: `feature/dualshock-motion-touchpad`

Development base: `master`. Later documentation merges may advance the graph merge-base without changing the feature's functional baseline.

## Scope

The branch advertises extended controller capabilities to Sunshine and carries touchpad, gyroscope and accelerometer events through the existing input stream. Previously the macOS client sent ordinary controller state/rumble but did not register controller type/capabilities or handle `moonlight-common` motion-state requests, so a host could not request these data streams.

There are two independent input implementations:

- `ControllerSupport` uses Apple's GameController API and works from the capabilities exposed by `GCController`/`GCPhysicalInputProfile`.
- `HIDSupport` directly parses DualShock 4 USB/Bluetooth HID reports, including factory calibration and filtering. This new direct-HID motion/touch implementation does not extend the existing DualSense (PS5) parser.

## Protocol and callback flow

```text
Sunshine requests motion state/rate
  -> moonlight-common-c setMotionEventState callback
  -> Connection.ClSetMotionEventState
  -> stream-scoped StreamViewController callback proxy
  -> ControllerSupport or HIDSupport
  -> timer/native HID processing
  -> LiSendControllerMotionEventCtx(input context)

controller input/touch
  -> GameController callback or IOHID report callback
  -> controller arrival/capability advertisement
  -> LiSendControllerEventCtx / LiSendControllerTouchEventCtx
```

`Connection.h/.m` adds the callback bridge. `StreamViewController.m` forwards it through the stream-generation proxy, then chooses the same backend already selected for normal controller input. No global `moonlight-common` input API is used: both backends bind the current `PML_INPUT_STREAM_CONTEXT` and call the `...Ctx` functions, preserving per-connection ownership.

## Component responsibilities

- `Limelight/Input/Controller.h`: per-GameController arrival, timers, last motion samples, gyro-rest state and two touch positions.
- `ControllerSupport.h/.m`: capability advertisement, GameController touch/motion conversion, active controller mask, neutral/release behavior, lifecycle cleanup and corrected button transitions.
- `HIDSupport.h`, `HIDSupport_Internal.h`, `HIDSupport.m`: direct-HID request rates, DS4 calibration/filter state, touch tracking, report validation, arrival and reconnect behavior.
- `Connection.h/.m`: registers `setMotionEventState` in `CONNECTION_LISTENER_CALLBACKS` and forwards the C callback to Objective-C.
- `StreamViewController.m` and `_Internal.h`: route the callback to the active input backend while rejecting callbacks from an obsolete stream generation.
- `moonlight-common/moonlight-common-c`: supplies `LI_CCAP_*`, controller-arrival/touch/motion event APIs and the host-driven callback; the submodule revision is unchanged by this branch.

## Arrival and capabilities

Extended input is not sent until the backend has an input context and successfully calls `LiSendControllerArrivalEventCtx`.

GameController derives player number, controller type, supported buttons and capabilities from the actual `GCController`. It identifies `GCDualShockGamepad` as PlayStation and `GCXboxGamepad` as Xbox; touchpad click/contact, accelerometer, gyroscope, analog-trigger, rumble and optional buttons are advertised only when exposed by the APIs. Multi-controller arrival and state packets use the branch's active connected-player mask instead of recomputing a potentially stale global mask.

Direct HID advertises one PlayStation controller (`player 0`, mask `1`) with analog triggers, rumble, touchpad, gyro and accelerometer capabilities. It is only active when the direct controller driver is selected.

The `reportedArrival` flags are session state, not physical-device identity. Replacing an input context clears arrival and extended state so the controller is advertised again to the new connection.

## Touchpad

GameController reads `GCInputDualShockTouchpadOne/Two` and the touchpad button from the physical input profile. Contact coordinates arrive in the GameController `[-1, 1]` space and are converted to Moonlight's normalized `[0, 1]` coordinates with Y inverted. The last position is retained so an `UP` event uses the final non-zero point. The implementation infers contact activity from non-zero axes; consequently an exact `(0, 0)` GameController sample is indistinguishable from no contact and is a known API-path limitation.

Direct HID reads both DS4 contacts from `PS4StatePacket_t`. Bit 7 of each touch counter is the inactive flag; 12-bit coordinates are normalized using the DS4 surface dimensions `1920 x 920`. Each contact has a stable pointer ID (`0` or `1`), and transitions generate `DOWN`, `MOVE` and `UP`. The physical touchpad click remains a normal `TOUCHPAD_FLAG` controller button.

## Motion: GameController backend

Sunshine's requested report rate creates or invalidates a main-run-loop `NSTimer` per motion type. Sensors requiring manual activation are active only while at least one timer exists.

- Accelerometer samples use `GCController.motion.acceleration`, suppress identical repeats, invert X/Y/Z and multiply by standard gravity (`9.80665`) before sending.
- Gyroscope samples convert radians/s to degrees/s and remap GameController axes to `(x, z, -y)`. Rest hysteresis enters at at most `1.0 dps` after eight timer samples and exits above `1.5 dps`; transitions to rest send a single neutral sample and identical later samples are suppressed.
- Disabling gyro reporting after it was active sends a zero vector to release remote state.

This path uses the rate requested by Sunshine directly as the timer frequency. The code does not clamp a non-zero requested rate; preserving the host-negotiated rate is therefore an invariant, but unusually high rates should be tested for timer cost.

## Motion: direct HID backend

Every valid native DS4 report is processed before transmission throttling. This is deliberate: filtering at the native HID rate avoids making filter behavior depend on Sunshine's requested network report rate.

### Calibration and units

On device match, the backend requests DS4 factory calibration feature report `0x02` (USB) and falls back to `0x05` (Bluetooth). It derives bias/scale for three gyro and three accelerometer axes and rejects empty or implausible data (large bias or scale more than 50% from unity). Invalid/unavailable calibration falls back to the packet's nominal scaling rather than blocking motion.

Gyro values are bias-corrected and converted to degrees/s (`/16`). Accelerometer values are bias-corrected and converted to m/s² using `9.80665 / 8192`, with per-axis factory scale when valid.

### Gyro filtering and rest detection

- A five-sample per-axis median filter processes the native roughly 260 Hz reports and rejects bursts lasting up to two reports.
- Rest entry requires magnitude at most `2 dps` for `30 ms`.
- Rest exit is immediate at `8 dps` or after magnitude remains above `3 dps` for `25 ms`; this prevents short noise bursts while retaining deliberate low-speed movement with a small delay.
- The first/different filtered value is sent only when due at Sunshine's requested rate. Entry into rest makes the zero sample immediately due; duplicate samples are suppressed.

Accelerometer reports are calibrated and only rate-limited; they do not use the gyro median/rest filter.

## HID report hardening

The parser accepts the known USB state report and DS4 Bluetooth state report IDs, requires the Bluetooth HID-present bit, ignores the disconnect message and unknown IDs, and checks `stateOffset + sizeof(PS4StatePacket_t)` before dereferencing. Truncated packets are logged and ignored.

Stick axes use a small center normalization/deadzone, while trigger bytes remain independent. Only the two real button bits in the third button byte participate in state-change detection; bits 2-7 are the DS4 rolling hardware report counter and must remain ignored, otherwise a reliable controller packet would be queued for every HID report. Ordinary buttons/sticks/triggers are enqueued before high-rate touch/motion data so gameplay controls win under constrained network capacity.

## Lifecycle and invariants

- `shouldSendInputEvents == NO` gates arrival and state. Transitioning from enabled to disabled sends neutral controller state and a zero gyro when applicable.
- Setting a new input context clears arrival, requested motion rates and filter/touch state. Do not reuse a context-bound arrival flag across stream sessions.
- A GameController disconnect unregisters callbacks, stops timers/sensors, releases neutral state, removes the controller, updates the active mask and reassigns player indices as existing code requires.
- A direct-HID physical disconnect clears buttons, sticks, triggers, touch/calibration/filter state and arrival, then attempts a neutral packet. It intentionally preserves Sunshine's requested gyro/accelerometer rates because the host normally requests them once per virtual-controller session; a physical reconnect can therefore resume without a second host request.
- Cleanup, context replacement and physical reconnect are different events. Do not collapse their reset policies.
- All extended sends must use the active connection's input context, and arrival must precede touch/motion events.
- Motion callbacks must continue through the stream-scoped proxy so an old `Connection` cannot control the replacement session's controller timers.

## Known limitations and uncertain behavior

- Direct parsing is implemented for DualShock 4 only; the existing DualSense parser still handles ordinary controller state without this branch's direct-HID touch/motion extension.
- GameController contact activity uses `(x,y) != (0,0)` as its sentinel, so the exact center cannot be represented reliably on that path.
- No user-facing calibration control or persistent calibration exists; DS4 factory data is read on device match and kept in memory.
- The code contains no automated sensor trace/replay tests, and the commit history does not establish which macOS versions, DS4 hardware revisions, transports or Sunshine versions were physically validated.

## Verification

Build both controller configurations and test against a host that requests controller motion:

1. Build the `Moonlight for macOS` scheme with the submodule and XCFramework dependencies present.
2. With the system/GameController driver, connect a DS4; verify arrival, ordinary controls, touch click, one- and two-finger contact, gyro and accelerometer. Stop and restart motion, then disconnect/reconnect the controller and stream.
3. Repeat with the direct HID driver over both USB and Bluetooth. Logs should show PlayStation arrival, calibration status, requested/native rates and only bounded diagnostic samples.
4. Hold the controller still: remote gyro must settle once to zero without a continuing reliable-packet stream. Move slowly through the hysteresis boundary and make a fast movement; verify neither drift nor lost intentional motion.
5. Exercise triggers independently near centered sticks, touch at edges, simultaneous contacts, controller removal while touching/moving, input-capture disable, stream reconnect and multiple controllers on the GameController path.
6. Feed or capture a short/invalid Bluetooth report if possible and confirm it is ignored without state corruption or crash.

There is no committed unit/UI test target. A future upstream PR would benefit from separating the protocol callback plumbing from DS4-specific parsing and adding deterministic report fixtures for calibration, truncation, filtering and lifecycle resets. Internal branch documentation must not be included in that PR.
