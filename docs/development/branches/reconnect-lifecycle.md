# Reconnect lifecycle serialization

Branch: `fix/reconnect-lifecycle`

Development base: `master`. Later documentation merges may advance the graph merge-base without changing the fix's functional baseline.

## Scope

This fix makes reconnect wait for the old native connection teardown instead of treating the asynchronous `Connection.terminate` call as if it had completed. It also makes `Connection` and `StreamManager` stop operations idempotent, preserves every completion registered at those layers, and prevents a transient AppKit fullscreen state from being saved as windowed during reconnect.

The history and code show the unsafe ordering, but do not contain a reproducible original incident. Before the fix, `StreamManager.stopStream` invoked `Connection.terminate`, which scheduled `LiStopConnectionCtx()` asynchronously and returned immediately. `attemptReconnectWithReason:` then proceeded to controller cleanup and `prepareForStreaming`; a new `Connection` could therefore be created while teardown of the embedded native context from the old object was still pending. Defensive callers could also invoke `terminate` more than once for the same context, even though the code now explicitly records that `LiStopConnectionCtx()` is not safe to call twice.

## Changed components

- `Limelight/Stream/Connection.h/.m`: adds `terminateWithCompletion:`, coalesced termination state and completion storage around the native `ML_CONNECTION_CONTEXT`.
- `Limelight/Stream/StreamManager.h/.m`: adds `stopStreamWithCompletion:`, coalesced manager stop state and a completion boundary over `Connection` teardown.
- `Limelight/macOS/ViewControllers/StreamViewController+Diagnostics.m`: reconnect now uses that boundary, validates reconnect generation/state after teardown, adds a 15-second teardown watchdog, and takes a safer presentation-mode snapshot.

Existing generation forwarding in `StreamViewController.m`, window-mode application in `StreamViewController.m`/`+WindowModes.m`, and lifecycle fields in `StreamViewController_Internal.h` are not introduced by this fix, but they are required context for the solution.

The controller-level close path also uses `stopStreamWithCompletion:` now. It keeps the controller alive until native teardown completes and does not treat the asynchronous compatibility `stopStream` call as a completed stop. Repeated close completions are registered with the manager boundary instead of being dispatched immediately.

## Connection termination

`terminate` remains the compatibility entry point and delegates to `terminateWithCompletion:nil`.

`terminateWithCompletion:` synchronizes on the `Connection` object and maintains three pieces of state:

- `_terminationStarted`: exactly one caller becomes responsible for native teardown;
- `_terminationCompleted`: later callers know teardown has passed its completion boundary;
- `_terminationCompletions`: copied blocks registered before completion.

The first caller marks termination started, optionally stores its completion, then calls thread-safe `LiInterruptConnectionCtx()` outside the lifecycle lock so a blocking `LiStartConnectionCtx()` can be interrupted. Microphone teardown is performed once. Native stop is dispatched to a high-priority global queue because termination can be requested from inside `moonlight-common` and must not deadlock or block that caller.

The async block captures `self` strongly. This is required because `_connectionContext` is embedded inside the Objective-C object; the pointer passed to `LiStopConnectionCtx()` would become invalid if `Connection` were released early. After native stop it unregisters the context-to-object mapping, marks completion under `@synchronized`, drains a snapshot of all registered completion blocks, and only then releases the strong local lifetime.

The obsolete `_initLock` Objective-C ivar was removed. It had never been acquired, and a shutdown crash was symbolicated to `Connection .cxx_destruct` attempting to release that ivar after native context teardown. Removing an unused retainable object immediately adjacent to the embedded native context also removes that invalid destructor operation; lifecycle serialization is provided by the explicit state and process-wide lifecycle lock described here.

If termination is already in progress, a caller only appends its completion and returns. If it has completed, a new completion is dispatched asynchronously on a default global queue. Completion execution therefore has no main-queue guarantee; UI callers must dispatch explicitly.

## StreamManager stop

`stopStream` delegates to `stopStreamWithCompletion:nil`. The completion-aware method uses the analogous `_stopStarted`, `_stopCompleted` and `_stopCompletions` state under `@synchronized(self)`.

The first stop request atomically:

1. captures the current `Connection` strongly;
2. cancels the `StreamManager` operation and its connection queue;
3. clears the queue reference and callbacks to prevent later startup/callback work;
4. calls the captured connection's `terminateWithCompletion:`.

Manager stop completes only when connection termination invokes `finishStop`. `finishStop` marks the manager completed, snapshots and drains all manager completions. If no `Connection` has been created yet, it completes immediately; the existing cancellation and nil-callback guards prevent the delayed main-thread creation block from starting one afterward.

Concurrent manager stop requests converge on the same operation and retain their completion blocks. As with `Connection`, completions are not assigned a specific queue.

## Native lifecycle lock and clipboard

`gConnectionLifecycleLock` is a process-wide `os_unfair_lock`. It serializes the full `LiStartConnectionCtx()` call, `LiStopConnectionCtx()`, and clipboard control operations (`bind`, `unbind`, snapshot and send) that act on connection/control contexts. This prevents those native operations from running concurrently across connection objects.

The lock alone does not establish the required old-stop-before-new-start ordering: whichever asynchronous operation acquires it first would win. The new completion chain supplies that ordering for reconnect. `LiInterruptConnectionCtx()` deliberately remains outside the lock so it can unblock an in-progress start. Clipboard operations capture `self` explicitly when setting the thread connection context, and their shared lifecycle lock prevents them from using the native context concurrently with stop.

## Reconnect sequence

The implemented reconnect path is:

```text
reconnect request
  -> snapshot presentation mode
  -> under controller synchronization: mark stop/reconnect and increment generation
  -> retain the current StreamManager as stoppingStreamManager
  -> stopStreamWithCompletion:
       cancel manager work/callbacks
       -> terminateWithCompletion:
            interrupt start; stop microphone
            -> lifecycle lock -> LiStopConnectionCtx(old context)
            -> unregister context; complete Connection and StreamManager stops
  -> dispatch reconnect continuation to main queue
  -> clear stop-in-progress; validate generation/reconnect/user-exit state
  -> detach old manager if still current
  -> tear down GameController/HID objects
  -> prepareForStreaming creates the new generation/session
```

`attemptReconnectWithReason:` captures `stoppingStreamManager` strongly. The completion cannot accidentally call stop on a later `self.streamMan`, and the manager/connection are kept alive through native teardown. The old manager reference is cleared only when it is still the controller's current manager.

`activeStreamGeneration` is incremented when reconnect begins and again by `prepareForStreaming`. The teardown completion checks the captured reconnect generation before starting a replacement. User exit calls `cancelPendingReconnectForUserExitWithReason:`, disables reconnect, clears reconnect state and increments the generation, so a late completion follows the abort path. Separately, `MLStreamScopedCallbacks` associates every new stream callback proxy with the generation created in `prepareForStreaming` and ignores callbacks from older sessions.

## Teardown watchdog

A main-queue block scheduled 15 seconds after the reconnect request covers the interval before the ordinary connect watchdog exists. It acts only if the captured generation is still active and both reconnect and stop remain in progress.

On timeout it logs the failure, clears `stopStreamInProgress` and `reconnectInProgress`, hides the reconnect overlay and shows a non-waitable error instructing the user to close the stream and retry. It does not cancel or force `LiStopConnectionCtx()`, start a replacement connection, or declare the native context safe. If teardown eventually completes, the continuation sees reconnect disabled and aborts. The watchdog is therefore UI recovery from an indefinitely spinning reconnect, not native teardown recovery.

## Presentation-mode preservation

`isWindowFullscreen` compares the fullscreen style bit explicitly with zero. Returning the raw masked value through Objective-C `BOOL` is incorrect on x86_64 because `NSWindowStyleMaskFullScreen` is bit 14 (`0x4000`), which truncates to zero in the 8-bit `BOOL` return value. The historical symptom is therefore possible even when the window style correctly contains the fullscreen bit.

Reconnect records mode `1` for observed fullscreen and `2` for observed borderless. If neither is currently observable, it falls back to the persisted `SettingsClass.displayModeFor(host)` value rather than always recording windowed (`0`). The observation reads the stream controller's own window and does not depend on key/main-window focus. This also matters while AppKit is entering or leaving fullscreen, when `styleMask` may temporarily look like a regular window.

The floating fullscreen/borderless control keeps its existing visibility and interaction rules. Before its auxiliary panel is attached or ordered onscreen, layout applies the final edge-anchored frame; this prevents the control from flashing at the panel's default bottom-left position without coupling menu availability to renderer startup or first-frame delivery.

When the replacement connection starts, `connectionStarted` consumes the preserved value only if the controller is still reconnecting, then clears `reconnectPreserveFullscreenStateValid`. Existing startup-mode code avoids a duplicate fullscreen toggle when fullscreen or a fullscreen transition is already primed, and otherwise applies fullscreen/borderless after the established startup delay.

## Invariants

- A particular `Connection` object's embedded `ML_CONNECTION_CONTEXT` must reach `LiStopConnectionCtx()` at most once.
- A reconnect must not call `prepareForStreaming` until the old `StreamManager` completion proves that its `Connection` passed `LiStopConnectionCtx()` and context unregistration.
- Multiple `Connection.terminateWithCompletion:` or `StreamManager.stopStreamWithCompletion:` calls must share one teardown and must not lose completions registered at those layers.
- `Connection` must remain alive while native teardown uses its embedded context; `StreamManager` and the exact stopping connection must likewise remain strongly owned through their completion chain.
- A controller close completion must not run until its `StreamManager` stop completion has crossed the native teardown boundary; the controller remains strongly owned until then.
- `LiStartConnectionCtx()`, `LiStopConnectionCtx()` and clipboard control operations must continue to share `gConnectionLifecycleLock`; interruption must remain possible without acquiring that lock.
- Clipboard control operations must re-check `Connection` termination state while holding `gConnectionLifecycleLock` and must not access or summarize a native control context after termination has started.
- Intentional stop and reconnect release clipboard ownership, including the native unbind when required, before requesting connection teardown.
- A reconnect continuation may mutate UI or create a new session only when its captured generation is still active, reconnect is still enabled/in progress, and no user disconnect superseded it.
- Stream callbacks must continue through generation-scoped proxies so an obsolete connection cannot alter the replacement session.
- AppKit's transient non-fullscreen style during a transition must not by itself force the replacement session to windowed mode; use observed fullscreen/borderless or the configured fallback as implemented.
- Fullscreen style-mask tests returning `BOOL` must normalize the masked integer with `!= 0`; the raw `0x4000` value must never be returned as `BOOL`.
- Controller/HID teardown and `prepareForStreaming` remain on the main queue after native stop completion.
- A watchdog timeout must not start a new session while the old native context may still be stopping.

## Edge cases and limitations

- Stop before `_connection` creation completes immediately at the manager layer; cancellation/nil-callback checks are what prevent later connection creation. Future startup edits must preserve those checks.
- A completion registered after either object has completed is asynchronous on a global queue, while pre-completion blocks run on the thread that finishes teardown. Callers must not assume queue affinity or synchronous delivery.
- The 15-second watchdog does not terminate a wedged native stop. The user can exit the UI, but the async teardown may remain blocked and retains its `Connection`.
- The presentation fallback uses configured mode whenever neither fullscreen nor borderless is observed, even outside a recorded fullscreen transition; `pendingWindowMode` is diagnostic only.
- No automated concurrency or reconnect tests are present, and repository history does not establish which failure mode, AppKit transition timing or host/network conditions reproduced the original issue.

## Verification

1. Build the `Moonlight for macOS` scheme and run with Thread Sanitizer in a development configuration when practical.
2. Trigger reconnect from the menu, connection-method/resolution/FPS/bitrate changes, automatic startup timeout, stalled payload and adaptive mitigation. Confirm exactly one native stop per old context and that the new `LiStartConnectionCtx()` log follows stop completion.
3. Request reconnect repeatedly and concurrently request window close/quit. Verify generation/user-exit guards prevent a replacement and no completion registered directly with `Connection`/`StreamManager` is lost.
4. Reconnect while windowed, borderless and fullscreen. Repeat while AppKit is entering and leaving fullscreen; the replacement must return to the intended mode without a spurious window shrink or duplicate toggle.
5. Exercise clipboard bind/unbind/snapshot/send during reconnect and confirm lifecycle-lock serialization, no use-after-free and no operation against an unregistered context.
6. Test with microphone enabled, controller and direct-HID input, then reconnect/disconnect during active input. Verify microphone/native stop precedes controller/HID replacement and stale callbacks are ignored.
7. Artificially delay native teardown beyond 15 seconds. Verify the error overlay appears, no new session starts, late completion aborts, and the window can be closed.
8. Stop before connection construction, during `LiStartConnectionCtx()`, after connection established and after stop already completed. Confirm idempotence and completion delivery at both lifecycle layers.

There is no committed test target, so log ordering, hardware/input behavior and AppKit transitions require manual validation.

## Upstream considerations

A possible upstream contribution should keep the lifecycle-layer APIs and reconnect ordering together: coalescing without waiting, or waiting without native idempotence, would leave part of the race intact. It should include deterministic tests with an injectable native stop/start boundary, concurrent completion registration, stop-before-connection, user cancellation and delayed teardown. Presentation-mode behavior may be separable if upstream prefers a smaller lifecycle PR. This internal document must not be included in an upstream PR.
