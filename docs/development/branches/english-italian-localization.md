# English and Italian localization

Branch: `feature/english-italian-localization`

Baseline: merge-base with `master` at `a9f20cc`

Functional commits: `c620ba1`, `8c5c8ac`

## Scope

The branch adds Italian as a selectable/system-detected language and completes English coverage in several surfaces that still contained Simplified Chinese or bilingual hard-coded text. It does not replace the existing localization architecture: it extends `LanguageManager`, adds Italian resource variants to the Xcode project, and converts affected call sites to stable English keys.

The second commit only revises three Italian translations (`Emulate Guide Button`, `Rumble Controller`, and `Running Game ID`).

## Resource and project structure

- `Limelight/macOS/en.lproj/Localizable.strings`: existing English bundle resource.
- `Limelight/macOS/zh-Hans.lproj/Localizable.strings`: existing Simplified Chinese bundle resource.
- `Limelight/macOS/it.lproj/Localizable.strings`: new Italian table covering the branch's programmatic/UI keys.
- `Limelight/macOS/{en,zh-Hans,it}.lproj/InfoPlist.strings`: localized microphone and input-monitoring permission descriptions; the Italian variant is new.
- `Moonlight.xcodeproj/project.pbxproj`: registers `it` in `knownRegions`, adds Italian to the `Localizable.strings` variant group, creates an `InfoPlist.strings` variant group for all three locales, and includes both groups in resources.

At this branch revision `plutil -lint` accepts all six `.strings` files. The Italian table intentionally has more entries than the existing English resource because many programmatic English values also live in `LanguageManager.en`; raw line/key counts are not an equality invariant.

## Selection and fallback

`AppLanguage` in `LanguageManager.swift` gains `.italian` with the stored display value `Italiano`. The existing picker in `SettingsStreamPane` iterates `AppLanguage.allCases`, so the new case appears without a separate view change. Selection is persisted through `@AppStorage("appLanguage")`.

`applyAppLanguage()` updates the `AppleLanguages` user default:

- System removes the override;
- English writes `en`;
- Italian writes `it`;
- Simplified Chinese writes `zh-Hans`.

It then posts `LanguageChanged`. `AppDelegateForAppKit` uses that notification to relocalize main menus/toolbars, while SwiftUI views observing the shared `LanguageManager` and explicit `localize()` calls update their own content. Some bundle-owned/system UI may still require recreation or application restart after changing `AppleLanguages`; the branch does not add a general restart prompt for language changes.

For System selection, only the first preferred language is inspected. Prefix `zh` selects `zh-Hans`, prefix `it` selects Italian, and every other locale selects English. This is a deliberate limited locale map, not normal iteration through the complete preferred-language list.

`LanguageManager.localize(key)` resolves in this order:

1. Simplified Chinese: in-code `zhHans` dictionary, then `zh-Hans.lproj`.
2. Italian: `it.lproj`.
3. English: in-code `en` dictionary, then `en.lproj`.
4. For any miss in Chinese or Italian, repeat the English dictionary/resource lookup.
5. If still missing, return the key itself.

English is therefore the development language and guaranteed cross-locale fallback. A missing Italian key must never fall back to previously hard-coded Chinese UI.

## Converted surfaces

The branch changes only surfaces proven by the diff:

- `ConnectionEditorViewController.m`: connection-method labels, columns, status and edit alert use `LanguageManager` through a local `MLString` macro.
- `StreamViewController+Diagnostics.m`: timeout/reconnect overlays, action buttons, log controls, filters and status summaries replace Chinese literals with `MLString` keys.
- `StreamViewController+MenuUI.m` and `+WindowModes.m`: in-stream menus, mouse/window/display/quality/audio/network/log controls, custom resolution/FPS dialogs and the fallback connection error become localizable.
- `SettingsAppPane.swift`: AWDL, reset and live/filtered log controls use `LanguageManager`; this also removes bilingual labels from the default UI.
- `DebugLogParser.swift`: category/domain names and user-facing parsed summaries are keys resolved at display time rather than embedded Chinese/English text.
- `Logger.m`: curated/default diagnostic lines are built from localized summary keys instead of Chinese literals. Raw protocol/system messages remain raw diagnostic data.
- `MicrophoneManager.swift`: microphone and AWDL helper status/error/prompt text routes through `LanguageManager`; duplicate manual bundle-selection code for AWDL prompts is removed.

These edits are part of localization coverage, not functional changes to connection, logging, microphone or stream behavior.

## Adding or changing a string

1. Use a stable English source key at the call site. Swift/SwiftUI should call `LanguageManager.shared.localize(...)` (or an observed instance); Objective-C files that already expose the helper may use their local `MLString` form.
2. Search both `LanguageManager.swift` dictionaries and all `*.lproj/Localizable.strings` files before adding a key. Do not create near-duplicates differing only in punctuation, ellipsis style or capitalization without a UI reason.
3. Put the Italian value in `it.lproj/Localizable.strings`. Ensure an English value exists in `LanguageManager.en` or `en.lproj`; update Simplified Chinese when the same UI remains supported there.
4. Preserve format placeholders exactly in type and count (`%@`, `%d`, `%lu`, `%.0f`, positional markers if introduced) and keep escaped newlines meaningful. Callers use localized strings as `stringWithFormat` formats.
5. Add privacy/Info.plist text to the locale's `InfoPlist.strings`, not the ordinary table.
6. Run `plutil -lint` for every edited strings file and build the app. Xcode must continue to see all variants through the variant groups.

There is no generation script or string catalog in this branch. The in-code English/Chinese dictionaries and `.strings` files are both authoritative for the keys they contain; consolidation would be a separate refactor, not something to do incidentally while translating.

## Invariants and edge cases

- Never remove the final English fallback or return an arbitrary non-English translation for an unsupported system locale.
- Do not translate persistence values, enum raw values, notification names, log classifier keys, connection method identifiers or other machine-facing tokens. Translate their display labels only.
- `LanguageChanged` is a string-named notification used by Objective-C and Swift code; renaming one side silently breaks live refresh.
- `AppLanguage` raw values are stored by `@AppStorage`; changing them is a preference migration, not a cosmetic edit.
- Preserve original unlocalized menu/toolbar titles in the AppDelegate relocalization path. Re-localizing an already translated title would make later language changes fail lookup.
- Debug-log classification should operate on stable raw/category identifiers. Localization belongs in `displayName`, curated summaries and controls, not in parsing predicates.
- System language detection currently ignores a supported second preference (for example, unsupported first locale followed by Italian) and maps all Chinese variants to Simplified Chinese. These are known limitations of the code.
- Translation completeness cannot be inferred from key counts because `LanguageManager` dictionaries overlap the resource tables. Missing keys are intentionally observable as English or, finally, the source key.

## Verification

1. Run:

   ```bash
   plutil -lint Limelight/macOS/{en,zh-Hans,it}.lproj/Localizable.strings
   plutil -lint Limelight/macOS/{en,zh-Hans,it}.lproj/InfoPlist.strings
   ```

2. Build the `Moonlight for macOS` scheme and confirm Italian resources are copied into the application bundle.
3. Select System, English, Italiano and Simplified Chinese from settings. Reopen windows where needed and verify settings, application menus/toolbars, connection editor, in-stream controls, timeout/reconnect overlays and both log viewers.
4. Start with macOS preferred language `it-*`, `zh-*`, English and an unsupported locale; verify System selection follows the documented mapping and unsupported locales use English.
5. Exercise microphone/AWDL permission denied and helper authorization/install errors, because these messages are conditional and easy to miss.
6. Trigger format-bearing strings (host names, latency, resolution, FPS, row counts and error codes) to detect placeholder mismatches or crashes.
7. Temporarily test a missing Italian key in a development build and confirm fallback to English, then restore the resource before committing.

No automated localization test or key-extraction/placeholder-parity tool is committed. For a future upstream PR, keep the functional localization/resource changes but exclude this internal document. A useful follow-up would be a read-only validation script that extracts call-site keys, checks English/Italian coverage and verifies format specifier parity.
