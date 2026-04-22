# Babbler

macOS menu bar app that switches typed/selected text between English and Russian keyboard layouts. Press the action key (Option by default, configurable) to swap the last typed word to the other layout.

## Architecture

- **AppKit app** with SwiftUI settings view, no SwiftUI App lifecycle
- Global keyboard event listener via `NSEvent.addGlobalMonitorForEvents`
- Carbon TIS APIs for input source management — must be called on the main thread
- Preferences stored in `UserDefaults` via `PreferenceStore` (global `preferenceStore` instance)
- `LanguageUtils.inputSources` must be initialized before use (`initInputSources()`)

## Key files

- `AppDelegate.swift` — entry point, event handling loop (`handleEvent`), language switch logic
- `KeyboardUtils.swift` — keyboard simulation (CGEvent), text replacement, action key config
- `LanguageUtils.swift` — TIS input source management, language detection, swap
- `StatusItemController.swift` — menu bar icon and menu
- `SettingsViewController.swift` — SwiftUI `SettingsView`, hosted via `NSHostingController`
- `PreferenceStore.swift` — UserDefaults wrapper for app preferences
- `KeyDictionary.swift` — EN<->RU character mapping dictionaries

## Threading

Carbon TIS APIs (`TISCopyCurrentKeyboardInputSource`, `TISSelectInputSource`, `String(describing: TISInputSource)`) are **not thread-safe**. Any code path that touches them must run on the main thread. Use `MainActor.run` when dispatching from a `Task`.

## Build

Xcode project, no SPM dependencies. Requires Accessibility permission at runtime.

## Code style

- Indent with **2 spaces**, not tabs
- Follow the existing style of each file when editing
