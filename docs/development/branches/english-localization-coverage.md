# English localization coverage

Branch: `fix/english-localization-coverage`

Baseline: `master`

## Scope

This branch removes Simplified Chinese and bilingual hard-coded user-facing text from macOS UI, diagnostics, logging, microphone and AWDL surfaces. Affected call sites use stable English localization keys, with English as the development-language fallback. It does not add another selectable language.

The branch also registers the existing English and Simplified Chinese `InfoPlist.strings` files as an Xcode variant group so localized privacy descriptions are copied into the application bundle.

## Converted surfaces

- `ConnectionEditorViewController.m`: connection method, columns, status and edit alerts.
- `StreamViewController+Diagnostics.m`: timeout/reconnect overlays, diagnostics, log controls and status summaries.
- `StreamViewController+MenuUI.m` and `+WindowModes.m`: stream menus, window/display/audio/network controls and dialogs.
- `SettingsAppPane.swift`: AWDL, reset and log controls.
- `DebugLogParser.swift` and `Logger.m`: display categories and curated summaries while preserving raw classifier tokens.
- `MicrophoneManager.swift`: microphone and AWDL helper prompts, states and errors.

## Fallback and invariants

`LanguageManager.localize()` resolves Simplified Chinese from its dictionary/resource and then falls back to the English dictionary/resource before returning the key. English selection continues to resolve English directly. Unsupported system locales continue to select English.

- Do not translate persistence values, notification names, parser/classifier identifiers or other machine-facing tokens.
- Preserve format placeholder types and counts in every locale.
- Keep `LanguageChanged` compatible across Objective-C and Swift callers.
- New UI should start from a stable English key and remain usable when a non-English translation is missing.

## Dependent locales

This branch owns the localization-key and English-fallback contract used by locale branches. When keys, placeholders, fallback order or resource membership change, review every maintained locale branch before release integration. Merge this branch into dependent locale branches first so translations are updated against the same source-key set rather than repaired only on `release/complete`.

## Verification

Run `plutil -lint` for the English and Simplified Chinese `Localizable.strings` and `InfoPlist.strings` files, inspect the Xcode resource variant groups, and build the `Moonlight for macOS` scheme. Manually check English and Simplified Chinese settings, menus, diagnostics, connection editor, log views, and microphone/AWDL error paths.

For an upstream contribution, include the functional localization cleanup but exclude this internal document.
