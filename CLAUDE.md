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

- `AppDelegate.swift` — app lifecycle, event handling loop (`handleGlobalSystemEvent`), keystroke recording (`wordRecord`, `lineRecord`), replacement orchestration (`performPendingReplacement`)
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

## Text switching algorithm

The switch happens in two phases separated by the input source change notification.

**Phase 1 — action key press** (main thread, `handleGlobalSystemEvent`):
1. `wordRecord` accumulates `(withShift, keyCode)` tuples for every key typed; `text` is its string mirror. `lineRecord`/`lineText` do the same but span the whole line without resetting on word boundaries.
2. On action key release, `pendingText` and `pendingCount` are snapshotted from whichever record applies (word or line), `isWaitingForSwitch = true`, then `InputSourceUtils.swapLang()` is called.
3. While `isWaitingForSwitch` is true, `handleGlobalSystemEvent` returns early — no further recording until the replacement is complete.

**Phase 2 — after the input source changes** (main thread, `performPendingReplacement` via `onKeyboardInputSourceChanged`):
1. **Translate** `pendingText` using `KeyboardUtils.translateText()` — maps each character through `enRuDictionary` or `ruEnDictionary` depending on the newly active layout. Must happen here on the main thread because `translateText` calls Carbon TIS APIs.
2. A **`Task`** (cooperative thread pool) runs `KeyboardUtils.replaceTypedText(translatedText, count)`:
   - Sends `count` × `Delete` key events to erase the original word.
   - Sleeps `keyboardDelay` (50 ms) to let the deletions land.
   - Calls `KeyboardUtils.injectText(translatedText)` — injects the translated string as a single Unicode keyboard event via `CGEvent.keyboardSetUnicodeString`. No TIS calls; safe off main thread.
3. Back on `@MainActor`: seeds `wordRecord`/`text` and `lineRecord`/`lineText` with the translated text so the next action key press can convert it back. Sets `isWaitingForSwitch = false`.

**Synthetic event filtering:**
All CGEvents synthesized by Babbler (Deletes + the Unicode inject) are stamped with `KeyboardUtils.syntheticEventMarker` (`0x4241_424C_4552`) via `setIntegerValueField(.eventSourceUserData, …)`. `handleGlobalSystemEvent` checks this field and returns immediately, preventing synthetic keystrokes from polluting the records regardless of delivery timing.

**Selected text path** (when `pendingCount == 0`):
If no typed record exists, the action key triggers `fetchSelectedText` — fires `Cmd+C`, waits 50 ms, reads the clipboard — then calls `typeText(selectedText)` which translates and injects in one shot. The old clipboard is restored after the copy.

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
