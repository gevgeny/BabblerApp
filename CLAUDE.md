# Babbler

macOS menu bar app that switches typed/selected text between English and Russian keyboard layouts. Press the action key (Option by default, configurable) to swap the last typed word to the other layout.

## Architecture

- **SwiftUI App lifecycle** (`BabblerApp.swift`) with `@NSApplicationDelegateAdaptor` for AppKit hooks
- Menu bar UI via `MenuBarExtra` with `.window` style (SwiftUI view, not `NSMenu`)
- Global keyboard event listener via `NSEvent.addGlobalMonitorForEvents`
- Carbon TIS APIs for input source management — must be called on the main thread
- Preferences stored in `UserDefaults` via `PreferenceStore` (global `preferenceStore` instance) and `@AppStorage` bindings in views
- `InputSourceUtils.inputSources` starts as `nil`; must call `InputSourceUtils.initInputSources()` before use

## Key files

- `AppDelegate.swift` — app lifecycle, event handling loop (`handleGlobalSystemEvent`), keystroke recording (`wordRecord`, `lineRecord`, `pendingRecord`)
- `BabblerApp.swift` — SwiftUI entry point, `MenuBarExtra` setup, clipboard history start/stop observer
- `Views/MenuView.swift` — menu bar dropdown: text-replace toggle, input source switcher, clipboard history, `MenuItemButtonStyle`
- `Views/SettingsView.swift` — settings form: action key, input indicator, clipboard history toggle, per-app input source mapping
- `KeyboardUtils.swift` — CGEvent keyboard simulation, text replacement, action key detection (word vs line action)
- `InputSourceUtils.swift` — TIS input source management: `initInputSources()`, `swapLang()`, `switchLang()`, `getCurrentInputSource()`, input source change callback
- `TISInputSourceExtension.swift` — Swift extensions on `TISInputSource` (`id`, `name`, `iconImage`, etc.)
- `PreferenceStore.swift` — `UserDefaults` wrapper; keys defined as top-level constants (`isTextReplaceEnabledKey`, `clipboardHistoryEnabledKey`, etc.)
- `ClipboardHistory.swift` — `ObservableObject` polling `NSPasteboard` every 0.5 s; deduplicating, capped history (default 20 items)
- `KeyDictionary.swift` — EN↔RU character mapping dictionaries
- `ImageUtils.swift` — menu bar icon generation; emoji map for common layouts, custom-drawn fallback; grayscale for secure-input state
- `SecurityInputUtils.swift` — polls IORegistry every 2 s to detect secure input mode; returns the app that enabled it
- `WorkspaceUtils.swift` — active app change callbacks; app enumeration for the settings picker
- `CrashLogger.swift` — installs global exception/signal handlers; writes logs to `~/Library/Application Support/Babbler/`

## Threading

Carbon TIS APIs (`TISCopyCurrentKeyboardInputSource`, `TISSelectInputSource`, `String(describing: TISInputSource)`) are **not thread-safe**. Any code path that touches them must run on the main thread. Use `MainActor.run` when dispatching from a `Task`.

## Gotchas

- `InputSourceUtils.inputSources` is `nil` until `initInputSources()` runs in `finishApplicationSetup()`. Code that validates saved preferences against available sources must guard against a `nil` value — otherwise it will wipe all saved data on first load.
- `ClipboardHistory.start()` is called conditionally based on `clipboardHistoryEnabledKey`; toggling the setting live goes through `BabblerApp.onChange`.

## Build

Xcode project, no SPM dependencies. Requires Accessibility permission at runtime.

## Code style

- Indent with **2 spaces**, not tabs
- Follow the existing style of each file when editing
