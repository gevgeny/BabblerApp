import Foundation
import Cocoa

let keyboardDelay = UInt64(50_000_000)

@objc class KeyboardUtils: NSObject {
    static private(set) var actionKeyCode = CGKeyCode(58);
    
    static private(set) var actionKeyFlag: NSEvent.ModifierFlags = .option;
    
    enum ActionKeyResult {
        case none
        case action        // plain Action key → switch last typed word
        case lineAction    // Shift + Action   → switch last typed line
    }

    static private var isActionKeyPressed = false
    static private var isShiftHeldWithAction = false

    /// Stamped onto every CGEvent we synthesize so `handleGlobalSystemEvent`
    /// can reject them regardless of timing — prevents synthetic keystrokes
    /// from being recorded into wordRecord / text.
    static let syntheticEventMarker: Int64 = 0x4241_424C_4552 // "BABBLER"

    static func setActionKey(code: UInt16) {
        actionKeyCode = CGKeyCode(code)
        switch code {
        case Key.option, Key.rightOption:
            actionKeyFlag = .option
        case Key.control, Key.rightControl:
            actionKeyFlag = .control
        default:
            actionKeyFlag = .option
        }
    }
    
    static func loadActionKeyFromPreferences() {
        let code = preferenceStore.getSwitchKeyCode()
        setActionKey(code: code)
    }
    
    static func addGlobalEventListener(_ callback: @escaping (NSEvent) -> Void) -> Void {
        // NSEvent.addGlobalMonitorForEvents delivers on a background thread.
        // Dispatch to main so that handleEvent can safely call Carbon TIS APIs
        // (which assert they run on the main queue) and mutate AppDelegate state
        // without data races.
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .flagsChanged]) { event in
            DispatchQueue.main.async { callback(event) }
        }
    }
  
    static func checkActionKeyPress(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> ActionKeyResult {
        if flags.contains(actionKeyFlag) && code == actionKeyCode {
            // Action key pressed — record whether Shift is also held
            isActionKeyPressed = true
            isShiftHeldWithAction = flags.contains(.shift)
            return .none
        } else if code == actionKeyCode && isActionKeyPressed {
            // Action key released — fire result
            let withShift = isShiftHeldWithAction
            isActionKeyPressed = false
            isShiftHeldWithAction = false
            return withShift ? .lineAction : .action
        } else if isActionKeyPressed && flags.contains(actionKeyFlag) {
            if isModifierKey(code) {
                // A modifier toggled while action key is held.
                // Only ever turn isShiftHeldWithAction ON — never clear it here.
                // Clearing it when Shift releases before Option would wrongly downgrade
                // the pending lineAction to a plain action.
                if flags.contains(.shift) {
                    isShiftHeldWithAction = true
                }
            } else {
                // A regular key (e.g. arrow, click) was pressed while action held — cancel
                isActionKeyPressed = false
                isShiftHeldWithAction = false
            }
            return .none
        } else {
            isActionKeyPressed = false
            isShiftHeldWithAction = false
            return .none
        }
    }

    private static func isModifierKey(_ code: UInt16) -> Bool {
        switch code {
        case Key.shift, Key.rightShift, Key.option, Key.rightOption,
             Key.control, Key.rightControl, Key.command, Key.capsLock, Key.function:
            return true
        default:
            return false
        }
    }

    static func replaceTypedText(_ text: String, count: Int) async {
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap

        // Delete the recorded characters one by one, stamped so the monitor ignores them
        for _ in 0..<count {
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: false)
            eventDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            eventUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
        }

        try? await Task.sleep(nanoseconds: keyboardDelay)

        // Inject the pre-translated string as a single Unicode event.
        // We do NOT call typeText/translateText here — those touch TIS APIs
        // which require the main thread, and this function runs on the cooperative pool.
        injectText(text)
    }
    
    static func fetchSelectedText(_ callback: @escaping (String) -> Void) -> Void {
        // Save current text from clipboard
        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        NSPasteboard.general.clearContents()
        
        // Fire Cmd+C
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap
        let eventDown = CGEvent(keyboardEventSource: src, virtualKey: Key.c, keyDown: true)
        let eventUp = CGEvent(keyboardEventSource: src, virtualKey: Key.c, keyDown: false)
        eventDown?.flags = CGEventFlags.maskCommand;
        eventDown?.post(tap: loc)
        eventUp?.post(tap: loc)
        
        Task {
            // Wait till text copied
            try? await Task.sleep(nanoseconds: keyboardDelay)

            // All NSPasteboard access and the callback must run on the main thread.
            // NSPasteboard (like all AppKit objects) is not thread-safe, and the
            // downstream callback calls Carbon TIS APIs which also require the main thread.
            await MainActor.run {
                let newClipboardText = NSPasteboard.general.string(forType: .string) ?? ""

                // Restore old clipboard contents
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(clipboardText, forType: .string)

                callback(newClipboardText)
            }
        }
    }
    
    static func translateText(_ text: String) -> String {
        // Decide mapping direction based on the current (target) input source
        // If current input source is Russian, we convert from EN -> RU
        // Otherwise, convert from RU -> EN
        guard let currentSource = InputSourceUtils.getCurrentInputSource() else { return text }
        let targetIsRussian = InputSourceUtils.isRussian(currentSource)
        let mapper = targetIsRussian ? enRuDictionary : ruEnDictionary

        let translated = text.map { ch -> String in
            let s = String(ch)
            if let mapped = mapper[s] {
                return mapped
            } else {
                return s
            }
        }
        return translated.joined()
    }

    /// Translate `text` (requires main thread) then inject. Call only from main thread.
    static func typeText(_ text: String) {
        injectText(translateText(text))
    }

    /// Inject `text` as a single Unicode keyboard event. Thread-safe — no TIS calls.
    static func injectText(_ text: String) {
        let utf16Chars = Array(text.utf16)
        let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true)
        event1?.flags = .maskNonCoalesced
        event1?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event1?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        event1?.post(tap: .cghidEventTap)

        let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false)
        event2?.flags = .maskNonCoalesced
        event2?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event2?.post(tap: .cghidEventTap)
    }
}

