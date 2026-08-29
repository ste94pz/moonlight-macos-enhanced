# Complete release integration

Branch: `release/complete`

Development base: `master`. The composition below is authoritative; use the Git graph when exact integration commits are needed.

## Purpose and composition

`release/complete` is the distributable integration branch. It combines independently maintained features through explicit merge commits and owns only the build/packaging changes needed by the complete product. New feature behavior should not be developed here.

The release currently integrates:

- `feature/dualshock-motion-touchpad` for DualShock motion and touch input;
- `fix/english-localization-coverage` for stable English keys and fallback coverage;
- `feature/background-controller-input`, which depends on English localization coverage, for optional controller-derived input while the stream window is unfocused;
- `feature/italian-localization`, which depends on the English coverage branch, for Italian selection and resources;
- `fix/reconnect-lifecycle` for serialized stream teardown and reconnect;
- release-owned build and packaging support.

Published ancestry still contains the earlier combined localization implementation. It is historical only: current ownership is split between English coverage and the dependent Italian locale branch.

The authoritative feature documents present in this branch are:

- `docs/development/branches/dualshock-motion-touchpad.md`
- `docs/development/branches/english-localization-coverage.md`
- `docs/development/branches/background-controller-input.md`
- `docs/development/branches/italian-localization.md`
- `docs/development/branches/reconnect-lifecycle.md`

## Release-only delta

Release-owned, non-feature work consists of:

- `scripts/build_release.sh` builds and packages native, arm64, x86_64 or universal Release products.
- `scripts/build_awdl_privileged_helper.sh` changes the zsh `ARCHS` expansion to `${=ARCHS}`, allowing the space-separated `arm64 x86_64` value to produce both helper slices during a universal build.
- `.gitignore` adds `dist/` for packaged local output.
- `--debug` runs the normal Debug scheme without release packaging or architecture verification.

Feature merges should preserve source-branch behavior exactly. Any integration conflict or release-only application change must be reviewed explicitly and recorded here instead of being hidden in a merge resolution.

## Build helper

Prerequisites are the same as the main project: initialized `moonlight-common-c`, downloaded FFmpeg/Opus/SDL2 XCFrameworks under `xcframeworks/`, Xcode/command-line tools, and SwiftPM access/cache for OpenSSL 3.6.1. `Limelight/Version.xcconfig` must exist before invoking the helper; normal Xcode work or `Limelight/build-number.sh` creates it.

Run from the repository root:

```bash
./scripts/build_release.sh --arch native
./scripts/build_release.sh --arch arm64
./scripts/build_release.sh --arch x86_64
./scripts/build_release.sh --arch universal
./scripts/build_release.sh --arch universal --dmg
./scripts/build_release.sh --debug
```

Options after `--` are appended to `xcodebuild`, for example an unsigned verification build:

```bash
./scripts/build_release.sh --arch native -- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The helper:

1. resolves the requested architecture (`native` uses `uname -m`);
2. backs up `Limelight/Version.xcconfig`, generates the build number before Xcode reads it, and restores the file on success or failure;
3. invokes the `Moonlight for macOS` Release scheme with a repository-local derived-data directory and the resolved OpenSSL artifact search path;
4. auto-disables signing if the project's team has no matching private key, unless signing flags were supplied explicitly;
5. verifies both `Moonlight.app/Contents/MacOS/Moonlight` and the embedded AWDL helper exist and contain every requested architecture using `lipo`;
6. replaces only the architecture-specific app at `dist/Moonlight-macOS-<variant>.app` using `ditto`;
7. optionally creates a DMG with `create-dmg`, falling back to `hdiutil`.

With `--debug`, the helper instead runs the scheme's Debug configuration for
the standard `platform=macOS` destination, leaves build products in Xcode's
standard Derived Data location, and skips release verification and packaging.
This mode cannot be combined with `--arch` or `--dmg`; arguments after `--`
are still forwarded to `xcodebuild`.

Build products live under ignored `build/` and `dist/`. Override them with `BUILD_DIR`, `DERIVED_DATA_PATH` and `OUTPUT_DIR` when isolation is required. A signing identity may be selected through normal Xcode settings/arguments; `SIGNING_TEAM_ID` only affects the helper's identity-availability decision.

`bash -n scripts/build_release.sh`, `zsh -n scripts/build_awdl_privileged_helper.sh`, `--help`, and an unsigned native x86_64 Release build have been verified for this documentation pass. That build succeeded and the script verified x86_64 slices for both the main binary and AWDL helper. arm64, universal assembly, signing, `create-dmg` and `hdiutil` fallback were not executed.

## Feature interaction

The integrated features occupy separate functional boundaries: DualShock changes the input/connection callback path, background controller input separates controller-derived event gating from focus-sensitive physical keyboard/mouse gating, English coverage changes user-facing diagnostics/settings/menu call sites, Italian localization adds language selection and resources, and reconnect lifecycle changes stream teardown synchronization. Although several touch the stream UI area, the split localization branches make the call-site cleanup reusable without requiring Italian resources.

This separation has two consequences:

- controller motion/touch functionality must be tested under each supported UI language because errors, diagnostics and in-stream controls use the English coverage keys and locale resources;
- background controller input must remain subordinate to stream readiness and teardown state: losing focus may preserve controller input when enabled, but reconnect or stop must disable it and clear the old input context;
- localization changes to diagnostics must not alter raw tokens or callback/lifecycle behavior used to debug the controller path.

Italian localization deliberately depends on `fix/english-localization-coverage` and integrates `feature/background-controller-input` so it can own the Italian values for that feature's UI keys. Every current source tip must be an ancestor of `release/complete` before distribution.

## Release invariants

- Integrate feature/fix corrections on their owning branch first, then merge them explicitly into `release/complete`.
- Keep release-direct changes limited to integration, packaging and complete-build logic; record any exception here.
- Preserve exact source-feature content unless a merge conflict requires an explicit, reviewed integration decision.
- Do not silently add another branch to the release composition; update this document whenever composition changes.
- A universal app is valid only when both the main executable and embedded AWDL helper contain arm64 and x86_64 slices; the helper's `${=ARCHS}` behavior is required for that invariant.
- `Version.xcconfig` restoration must occur on both build success and failure. Do not leave a generated build number as a tracked/source change.
- Release output replacement must remain scoped to the computed app path inside `OUTPUT_DIR`; do not broaden cleanup targets.
- Localization resource membership and DualShock extended callback wiring must survive project-file or common-library updates.

## Integration verification

Before distributing a complete build:

1. Confirm ancestry and composition with `git log --first-parent`, `git merge-base --is-ancestor` and diffs against each source branch.
2. Run shell syntax checks and build native plus every architecture intended for release. For universal, inspect main/helper with `lipo -archs` even though the helper script already fails missing slices.
3. Launch the packaged app, switch System/English/Italian/Chinese, and verify settings, menus, connection editor, diagnostics, microphone/AWDL prompts and Italian privacy strings.
4. Test DualShock 4 GameController and direct-HID paths, USB and Bluetooth where available: ordinary controls, touch/click, gyro/accelerometer, capture disable, device reconnect and stream reconnect.
5. With both HID and GameController drivers, test background controller input disabled and enabled while focus moves to another Moonlight window and another application. Include controller mouse emulation, live preference changes, hot-plug, reconnect and disconnect; physical keyboard and mouse input must remain focus-gated.
6. Cross-test: exercise controller diagnostics and failures while Italian is selected, verify the background-input setting text, and confirm localized presentation does not change raw diagnostic/classifier values.
7. Test host launch/resume, video, direct/enhanced audio, mouse/keyboard, disconnect/reconnect and app termination to catch regressions outside the directly affected areas.
8. If producing a DMG, mount it, copy the app, launch it under the intended signing/Gatekeeper conditions, and verify the embedded helper architecture/signature.

There is no automated unit/UI test target. Hardware sensor behavior, live language coverage, signing and packaging therefore require manual integration validation.

## Known limitations

- Only the current host's native unsigned x86_64 Release build was executed in this pass; other architecture/package claims above come from inspected script behavior, not a successful local artifact.
- The repository history does not record a complete hardware/locale/signing test matrix for every release composition.
