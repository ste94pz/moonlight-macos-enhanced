# Complete release integration

Branch: `release/complete`

Baseline: merge-base with the pre-documentation `master` at `a9f20cc`

## Purpose and composition

`release/complete` is the distributable integration branch. It combines independently maintained features through explicit merge commits and owns only the build/packaging changes needed by the complete product. New feature behavior should not be developed here.

The current tip `9166062` contains:

- `feature/dualshock-motion-touchpad` through `8711a47`, merged by `ede1458` and updated by `e9b3fce`;
- `feature/english-italian-localization` through `8c5c8ac`, merged by `f707165` and updated by `9166062`;
- direct release build commit `d3efaa6` (`build: add complete release build helper`).

`fix/reconnect-lifecycle` at `9d82bcc` is not an ancestor of this branch and is not part of the complete release.

The feature documentation was created after the merge commits above and is therefore not present in this branch. Its authoritative locations are:

- `feature/dualshock-motion-touchpad:docs/development/branches/dualshock-motion-touchpad.md`
- `feature/english-italian-localization:docs/development/branches/english-italian-localization.md`

Consult those branch:path objects for implementation details. They must be propagated only through a deliberate later feature integration, not by an undocumented docs-only merge.

## Release-only delta

Commit `d3efaa6` is the only direct non-merge delta from the integrated features:

- `scripts/build_release.sh` builds and packages native, arm64, x86_64 or universal Release products.
- `scripts/build_awdl_privileged_helper.sh` changes the zsh `ARCHS` expansion to `${=ARCHS}`, allowing the space-separated `arm64 x86_64` value to produce both helper slices during a universal build.
- `.gitignore` adds `dist/` for packaged local output.

No application behavior was resolved or modified directly during the feature merges. At the documented tips, the complete branch's DualShock-related files are byte-equivalent to their source feature branch, and the localization-related files are byte-equivalent to theirs.

## Build helper

Prerequisites are the same as the main project: initialized `moonlight-common-c`, downloaded FFmpeg/Opus/SDL2 XCFrameworks under `xcframeworks/`, Xcode/command-line tools, and SwiftPM access/cache for OpenSSL 3.6.1. `Limelight/Version.xcconfig` must exist before invoking the helper; normal Xcode work or `Limelight/build-number.sh` creates it.

Run from the repository root:

```bash
./scripts/build_release.sh --arch native
./scripts/build_release.sh --arch arm64
./scripts/build_release.sh --arch x86_64
./scripts/build_release.sh --arch universal
./scripts/build_release.sh --arch universal --dmg
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

Build products live under ignored `build/` and `dist/`. Override them with `BUILD_DIR`, `DERIVED_DATA_PATH` and `OUTPUT_DIR` when isolation is required. A signing identity may be selected through normal Xcode settings/arguments; `SIGNING_TEAM_ID` only affects the helper's identity-availability decision.

`bash -n scripts/build_release.sh`, `zsh -n scripts/build_awdl_privileged_helper.sh`, `--help`, and an unsigned native x86_64 Release build have been verified for this documentation pass. That build succeeded and the script verified x86_64 slices for both the main binary and AWDL helper. arm64, universal assembly, signing, `create-dmg` and `hdiutil` fallback were not executed.

## Feature interaction

The two features occupy separate functional boundaries: DualShock changes the input/connection callback path, while localization changes resources and user-facing diagnostics/settings/menu text. Although both affect the stream UI area, DualShock changes `StreamViewController.m`/its internal protocol and localization changes category files such as `+Diagnostics` and `+MenuUI`; the recorded merges required no integration-only code delta.

This separation has two consequences:

- controller motion/touch functionality must be tested under each supported UI language because errors, diagnostics and in-stream controls come from the localization feature;
- localization changes to diagnostics must not alter raw tokens or callback/lifecycle behavior used to debug the controller path.

There is no demonstrated functional dependency between the feature branches. Each remains based directly on `a9f20cc`, and each source tip is an ancestor of `release/complete`.

## Release invariants

- Integrate feature/fix corrections on their owning branch first, then merge them explicitly into `release/complete`.
- Keep release-direct changes limited to integration, packaging and complete-build logic; record any exception here.
- Preserve exact source-feature content unless a merge conflict requires an explicit, reviewed integration decision.
- Do not silently add `fix/reconnect-lifecycle` or any other branch to the release composition.
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
5. Cross-test: exercise controller diagnostics and failures while Italian is selected, and confirm localized presentation does not change raw diagnostic/classifier values.
6. Test host launch/resume, video, direct/enhanced audio, mouse/keyboard, disconnect/reconnect and app termination to catch integration regressions outside the two feature deltas.
7. If producing a DMG, mount it, copy the app, launch it under the intended signing/Gatekeeper conditions, and verify the embedded helper architecture/signature.

There is no automated unit/UI test target. Hardware sensor behavior, live language coverage, signing and packaging therefore require manual integration validation.

## Known limitations

- The feature documents are not yet propagated into this branch because they were committed after the recorded merges.
- General `master` documentation introduced after this branch diverged is likewise not present; this file must be read together with `master` documentation when maintaining the release.
- Only the current host's native unsigned x86_64 Release build was executed in this pass; other architecture/package claims above come from inspected script behavior, not a successful local artifact.
- The repository history does not record a complete hardware/locale/signing test matrix for tip `9166062`.
