# Background controller input

Branch: `feature/background-controller-input`

Base branch: `fix/english-localization-coverage`

## Scope

This branch adds a per-profile Input setting that allows controller-derived input to continue while the stream window is not focused. The option is disabled by default and applies to both the direct HID controller backend and Apple's GameController backend.

The feature depends on `fix/english-localization-coverage` because its settings row and explanatory text use the stable English-key fallback contract owned by that branch.

## Input gating

`HIDSupport.shouldSendInputEvents` remains the focus-sensitive gate for physical keyboard and mouse input. `HIDSupport.shouldSendControllerEvents` independently gates direct HID controller reports, including controller-driven mouse emulation. `ControllerSupport.shouldSendInputEvents` remains the corresponding GameController gate.

`StreamViewController.refreshControllerInputSendingState` resolves the runtime controller gate from three conditions:

- the stream has a ready input context and is not stopping or reconnecting;
- focused input capture is active; or
- the persisted `backgroundControllerInput` setting is enabled for the current host profile.

Stop, controller teardown and reconnect preparation always disable controller input and clear its input context regardless of the preference. Changing the preference while streaming posts `MoonlightControllerSettingsDidChange`, so an unfocused stream updates without requiring a focus cycle or reconnect.

## Persistence and localization

`Settings.backgroundControllerInput` is optional for compatibility with existing property-list profiles and resolves to `false` when absent. It follows the repository's global/per-host inheritance behavior.

This branch owns the English source keys and Simplified Chinese coverage. `feature/italian-localization` must integrate this branch before adding the Italian values for `Background Controller Input` and `Background Controller Input detail`.

## Verification

Build the `Moonlight for macOS` scheme and lint the English and Simplified Chinese string tables. Manually test both HID and GameController drivers with the option off and on:

- while the stream window is focused;
- after focus moves to another Moonlight window and to another application;
- with normal controller input and controller mouse emulation;
- while toggling the option during an active unfocused stream;
- after reconnect, disconnect and controller hot-plug transitions.

Confirm that physical keyboard and mouse events remain blocked while the stream window is unfocused and that no controller event is sent after stream teardown begins.

For an upstream contribution, include the functional change but exclude this internal document.
