# Repository guide

Moonlight macOS Enhanced is a native macOS streaming client for Sunshine-compatible hosts. This repository is the `ste94pz/moonlight-macos-enhanced` fork; `upstream` is `skyhua0224/moonlight-macos-enhanced`. Always run `git status --short --branch` before starting and confirm that edits are made on the intended branch.

## Read first

- General code navigation: `docs/development/ARCHITECTURE.md`.
- Git and upstream workflow: `docs/development/WORKFLOW.md`.
- Fork/branch index: `docs/development/README.md`.
- On a feature or release branch, also read the matching file under `docs/development/branches/` when present.
- For reconnect or stream-teardown work, read `docs/development/branches/reconnect-lifecycle.md` when the implementing branch is checked out or integrated.

## Code map

- `Limelight/macOS/`: AppKit/SwiftUI lifecycle, views, settings and localization.
- `Limelight/Network/`: discovery, pairing, HTTP and host session preparation.
- `Limelight/Stream/`: stream configuration, `moonlight-common` callbacks, audio and video.
- `Limelight/Input/`: keyboard, mouse, HID/GameController and haptics.
- `Limelight/Database/`: Core Data persistence and temporary models.
- `moonlight-common/`: Xcode wrapper plus the `moonlight-common-c` submodule.
- `scripts/`: build helpers; `.github/workflows/build.yml`: CI/release build.

The main path is UI/settings -> `StreamConfiguration` -> `StreamManager` -> `Connection` -> `moonlight-common-c` -> host, with callbacks returning video/audio/input-control events to the macOS implementations.

## Build and verification

Initialize dependencies and download the external XCFramework bundle as described in `README.md`, then use:

```bash
xcodebuild -project Moonlight.xcodeproj -scheme "Moonlight for macOS" -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Use `xcodebuild -list -project Moonlight.xcodeproj` for a quick project check and `xcodebuild ... analyze` for static analysis. There is currently no test target or committed automated unit/UI test suite; use the area-specific manual checks documented under `docs/development/branches/` and the CI architecture builds.

## Development rules

- Keep `master` close to `upstream/master`; start independent work on `feature/*` or `fix/*` from `master`.
- Integrate complete builds on `release/complete` with explicit `--no-ff` merges; do not normally develop feature behavior there.
- Preserve Objective-C/Swift bridging through `Limelight/Moonlight-Bridging-Header.h` and `Moonlight-Swift.h` call sites.
- Treat `Connection` contexts, stream teardown, input capture and UI/main-thread ownership as lifecycle-sensitive. Verify reconnect/disconnect paths, not only first connection.
- Do not edit the `moonlight-common-c` submodule as if it were ordinary parent-repository source; update its pinned commit deliberately.
- When a change materially alters architecture, behavior, invariants, interfaces, test requirements or fork-specific functionality, update the authoritative document in the same activity using a separate `docs:` commit.

## Upstream contribution policy

- `AGENTS.md`, `docs/development/` and fork-specific documentation are internal and normally must not be included in upstream pull requests.
- Keep internal documentation in `docs:` commits separate from functional commits. Do not mix code and internal documentation except when explicitly required.
- `feature/*` and `fix/*` are fork development branches, not necessarily direct upstream PR branches.
- Prepare an upstream contribution on a temporary `pr/*` branch created from the appropriate upstream branch, normally `upstream/master`, containing only upstream-bound commits.
- Do not cherry-pick internal documentation into `pr/*` unless explicitly requested.
