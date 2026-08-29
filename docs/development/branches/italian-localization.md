# Italian localization

Branch: `feature/italian-localization`

Base branch: `fix/english-localization-coverage`

## Scope

This branch adds Italian as a selectable and system-detected language on top of complete English localization coverage. It adds Italian resources and the minimum language-selection and Xcode project changes required to use them. Removal of hard-coded Simplified Chinese or bilingual UI belongs to the prerequisite English coverage branch. It also integrates maintained UI feature branches when Italian translations are required for their new keys.

## Resources and selection

- `Limelight/macOS/it.lproj/Localizable.strings` contains Italian programmatic and UI strings.
- `Limelight/macOS/it.lproj/InfoPlist.strings` contains Italian microphone and input-monitoring permission descriptions.
- `Moonlight.xcodeproj/project.pbxproj` registers `it` in `knownRegions` and adds Italian children to the existing localization variant groups.
- `AppLanguage.italian` uses the persisted display value `Italiano`; explicit selection writes `it` to `AppleLanguages`.
- System selection maps a first preferred language beginning with `it` to Italian, `zh` to Simplified Chinese, and other values to English.

Italian lookup uses `it.lproj`, then the English dictionary/resource fallback established by `fix/english-localization-coverage`, and finally the source key. Some bundle-owned UI may require recreation or application restart after `AppleLanguages` changes.

## Adding or changing strings

Use a stable English key at the call site and add its Italian value to `it.lproj/Localizable.strings`. Preserve format placeholders exactly in type and count. Privacy descriptions belong in `InfoPlist.strings`. Do not translate persistence values, enum identifiers, notification names, log classifier keys or other machine-facing tokens.

The Italian table can contain more entries than the English `.strings` file because English values also live in `LanguageManager.en`; raw key counts are not a completeness invariant.

## Prerequisite maintenance

The English coverage branch is the prerequisite and source of truth for keys and fallback behavior. Integrate it here before translating newly introduced UI or changing lookup behavior. Any English key or placeholder change requires a corresponding Italian coverage and format-parity review before this branch is integrated into `release/complete`.

`feature/background-controller-input` is integrated after the English coverage prerequisite. This branch owns the Italian values for `Background Controller Input` and `Background Controller Input detail`; future changes to those source keys must be merged from the feature branch before updating the translations here.

## Verification

Run `plutil -lint` for all English, Italian and Simplified Chinese `.strings` files, build the `Moonlight for macOS` scheme, and confirm `it.lproj` is copied into the app bundle. Test System, English, Italiano and Simplified Chinese selection, including `it-*` system preferences, format-bearing strings, menus, diagnostics, connection editor, log views, and microphone/AWDL permission paths.

For an upstream contribution, include functional resources and selection changes but exclude this internal document.
