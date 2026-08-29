# Architecture

This is a navigation guide to the repository as it exists on `master`. Branch-specific deltas belong under `docs/development/branches/`.

## System path

```text
AppKit/SwiftUI UI
  -> persisted/global-or-host settings and selected TemporaryHost/TemporaryApp
  -> StreamViewController builds StreamConfiguration
  -> StreamManager performs serverinfo and launch/resume
  -> Connection binds video/audio/control callbacks and calls moonlight-common-c
  -> Sunshine-compatible host

host callbacks
  -> Connection
  -> VideoDecoderRenderer / Core Audio / StreamViewController
  -> HIDSupport or ControllerSupport -> moonlight-common-c input context -> host
```

The non-obvious boundary is that `StreamManager` prepares the host session over HTTP, while `Connection` owns one `ML_CONNECTION_CONTEXT` and the real-time Moonlight protocol lifecycle. UI callbacks are scoped by `StreamViewController` so callbacks from a superseded stream generation are ignored.

## Bootstrap and UI lifecycle

`Limelight/macOS/Supporting Files/main.m` starts the AppKit app. `AppDelegateForAppKit` creates the storyboard main window, installs theme/language handling, opens SwiftUI settings through `SettingsWindowObjCBridge`, initializes controller navigation, presents first-run permissions, and saves Core Data on termination.

The main browsing flow is implemented by `HostsViewController` (discovery, manual hosts and pairing), `AppsWorkspaceViewController`/`AppsViewController` (host application list and launch selection), and `StreamViewController` (the stream window and lifecycle). `ContainerViewController` and `Main.storyboard` provide the containing navigation. `StreamViewMac` is the rendering/input view used by the stream controller.

`StreamViewController` is intentionally split into categories:

- the main `.m` file owns configuration, connection callbacks, teardown, clipboard ownership and high-level lifecycle;
- `+MouseCapture` owns pointer capture and free/locked mouse handoff;
- `+MenuUI` owns in-stream controls and shortcuts;
- `+Diagnostics` owns watchdogs, overlays and diagnostic collection;
- `+WindowModes` owns fullscreen/borderless/windowed transitions;
- `StreamViewController_Internal.h` is their shared private contract.

Changes here must preserve main-thread UI/controller teardown and reject stale callbacks during reconnect or close.

## Discovery, pairing and persistence

`Limelight/Network/` separates host operations from UI:

- `DiscoveryManager`/`DiscoveryWorker` and `MDNSManager` find and refresh hosts; `ConnectionEndpointStore` and `LatencyProbe` help select reachable endpoints.
- `HttpManager`, request/response types and `ServerInfoResponse` implement host HTTP operations.
- `PairManager`, `CryptoManager` and `IdManager` handle pairing identity and certificates.
- `AppAssetManager`/`AppAssetRetriever` retrieve box art; `WakeOnLanManager` sends wake packets.
- `StreamingSessionManager` publishes which host/app is actively streaming to the rest of the UI.

`DatabaseSingleton` owns the Core Data stack defined by `Limelight.xcdatamodeld`. `DataManager` maps persistent `Host`, `App` and `Settings` entities into `TemporaryHost`, `TemporaryApp` and `TemporarySettings` objects used across Objective-C UI/network code.

## Configuration

The settings UI is SwiftUI under `Limelight/macOS/ViewControllers/Settings*.swift`. `SettingsModel` exposes global or per-host state; `SettingsModel+Persistence` resolves storage/inheritance, while derived values and risk assessment are separated into their named extensions. `SettingsObjCBridge` is the supported Objective-C access layer.

At launch time, `StreamViewController.prepareForStreaming` combines the selected host/app, Core Data values, per-host `UserDefaults`, runtime display/connection overrides and capability decisions into `StreamConfiguration`. That object is the immutable-by-convention handoff through `StreamManager` to `Connection` and `VideoDecoderRenderer`. When adding a setting, trace all three layers: SwiftUI/model persistence, Objective-C bridge, and stream configuration consumption.

## Streaming session and moonlight-common

`StreamManager` generates the remote-input key, obtains `serverinfo`, verifies pairing, launches or resumes the host app, prewarms `VideoDecoderRenderer`, then creates `Connection` on a serial operation queue.

`Connection` translates `StreamConfiguration` into `SERVER_INFORMATION`/`STREAM_CONFIGURATION`, initializes `CONNECTION_LISTENER_CALLBACKS`, `DECODER_RENDERER_CALLBACKS` and `AUDIO_RENDERER_CALLBACKS`, and calls `LiStartConnectionCtx()` from the pinned `moonlight-common-c` API. It maps each `ML_CONNECTION_CONTEXT` back to its Objective-C owner because callback functions are C entry points and more than one lifecycle/context may exist during transitions. Shutdown must go through `terminate`/`LiStopConnectionCtx()` without releasing the context early; reconnect implementations must establish that teardown has completed before replacing the owning session. The branch-specific synchronization contract is documented in `branches/reconnect-lifecycle.md` when that branch is checked out or integrated.

`moonlight-common/moonlight-common.xcodeproj` builds the static `libmoonlight-common.a`; its source is the `moonlight-common/moonlight-common-c` Git submodule, currently sourced from `skyhua0224/moonlight-common-c`. Parent code includes its public and selected internal headers. Protocol additions therefore may require a deliberate submodule revision update and compatible callback/context plumbing in `Connection`.

## Video

`VideoDecoderRenderer` is the video callback implementation and presentation coordinator. It accepts codec setup/sample callbacks from `Connection`, uses VideoToolbox for hardware decode, and owns the native sample-buffer, Metal/MetalKit and compatibility presentation paths, including HDR/color metadata, frame pacing, VideoToolbox enhancement/interpolation and MetalFX where available. `RendererLayerContainer` hosts the renderer layers in the stream view.

Renderer selection and parameters originate in `SettingsVideoPane`, `SettingsStreamPane`, `SettingsModel` derived values and `StreamConfiguration`. A renderer change should be checked across codec negotiation, pixel format/HDR metadata, view/layer lifecycle, display changes and teardown; do not treat the large renderer as an isolated drawing utility.

## Audio and microphone

Audio callbacks are also implemented inside `Connection`. Opus multistream packets are decoded with the external Opus framework, then sent to either the legacy `AudioQueue`, a direct Core Audio `AudioUnit`, or the enhanced AVAudioEngine/EQ/reverb/downmix path. Channel negotiation includes stereo and multichannel layouts. `SettingsAudioPane` and related `StreamConfiguration` fields choose the runtime path.

`MicrophoneManager.swift` owns permissions/control-facing state. The conditional microphone implementation in `Connection` captures with AVAudioEngine, converts/encodes Opus and sends through `moonlight-common-c` when the pinned common library exposes the microphone control API. Test capture permission denial, start/stop and reconnect as separate cases.

## Input and controllers

`HIDSupport` is the macOS input hub for keyboard, mouse/scroll and the direct IOHID controller backend; its pointer, scroll and rumble responsibilities are split into `HIDSupport+*.m`, with shared state in `HIDSupport_Internal.h`. `CoreHIDMouseDriver.swift` provides the high-rate mouse path. `StreamViewController+MouseCapture` coordinates those events with window focus and the local cursor.

`ControllerSupport` uses Apple's GameController framework for system-managed controllers; `Controller` holds per-player state and `HapticContext` drives controller haptics. `StreamViewController` selects `ControllerSupport` for the system controller driver or direct `HIDSupport` otherwise, assigns the active `moonlight-common-c` input context after connection, and gates transmission with `shouldSendInputEvents`. Controller arrival/removal, input-capture disable, stream replacement and reconnect are all state transitions that must clear or re-advertise remote state.

## Localization

`LanguageManager.swift` stores the selected application language, sets `AppleLanguages`, posts `LanguageChanged`, and supplies programmatic SwiftUI strings. AppKit/storyboard strings and privacy descriptions use localized `.strings` resources under `Limelight/macOS/<locale>.lproj`. `AppDelegateForAppKit` relocalizes menus/toolbars, and relevant view controllers observe the language notification. English is the project development region; currently `master` contains English and Simplified Chinese resources. See a localization feature document when working on an additional locale.

## Build and dependencies

`Moonlight.xcodeproj` has one application target, `Moonlight for macOS`, depending on the nested `moonlight-common` static-library target. The deployment target is macOS 12 and Swift language version is 5. The shared scheme runs `Limelight/build-number.sh` as a pre-action; generated `Limelight/Version.xcconfig` is ignored. The application target also runs `scripts/build_awdl_privileged_helper.sh` and embeds its privileged helper.

Dependencies are:

- pinned `moonlight-common-c` submodule for the streaming protocol;
- OpenSSL Package 3.6.1 through Swift Package Manager (`Package.resolved` pins the revision);
- downloaded FFmpeg, Opus and SDL2 XCFrameworks under ignored `xcframeworks/`;
- Apple frameworks including AppKit/SwiftUI, VideoToolbox, AVFoundation/Core Audio, Metal/MetalKit/MetalFX, GameController, CoreHaptics and IOKit HID.

`.github/workflows/build.yml` builds signed-disabled arm64 and x86_64 products, verifies both the app and AWDL helper slices, packages per-architecture artifacts, and assembles a universal build. There is no test target in the shared scheme; builds, static analysis and targeted manual streaming tests are the available verification mechanisms.
