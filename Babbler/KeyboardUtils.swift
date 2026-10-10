import Foundation
import Cocoa
import os

let keyboardDelay = UInt64(50_000_000)

// ponytail: temporary logging for the fast-Option wrong-symbols bug; remove after the fix.
// DEBUG only — it logs typed text. Xcode console, or:
// /usr/bin/log stream --level debug --predicate 'subsystem == "eugene.Babbler"'
private let replaceLogger = Logger(subsystem: "eugene.Babbler", category: "replace")
func replaceLog(_ message: @autoclosure () -> String) {
#if DEBUG
    let text = message()
    replaceLogger.debug("\(text, privacy: .public)")
#endif
}

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
    // Secure input hides keyDown events from the global monitor, so compare the
    // system-wide keyDown counter between action key press and release instead.
    static private var keyDownCountAtActionPress: UInt32 = 0

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
            keyDownCountAtActionPress = keyDownCount()
            return .none
        } else if code == actionKeyCode && isActionKeyPressed {
            // Action key released — fire result
            let withShift = isShiftHeldWithAction
            let wasInterrupted = keyDownCount() != keyDownCountAtActionPress
            isActionKeyPressed = false
            isShiftHeldWithAction = false
            if wasInterrupted { return .none }
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

    private static func keyDownCount() -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
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

    private static func deleteLastTypedWord(_ src: CGEventSource?, _ loc: CGEventTapLocation) {
        let deleteDown = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: true)
        let deleteUp = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: false)
        
        deleteDown?.flags = CGEventFlags.maskAlternate;
        deleteDown?.post(tap: loc)
        deleteUp?.post(tap: loc)
    }
    
    private static func deleteTypedText(_ src: CGEventSource?, _ loc: CGEventTapLocation, _ record: [(withShift: Bool, code: UInt16)]) {
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap

        // Delete last typed text
        for _ in 1...record.count {
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: false)

            postSynthetic(eventDown, flags: [], loc)
            postSynthetic(eventUp, flags: [], loc)
        }
    }
    
    private static func typeRecordedText(
        _ record: [(withShift: Bool, code: UInt16)],
        _ src: CGEventSource?,
        _ loc: CGEventTapLocation
    ) {
        let actionUp = CGEvent(keyboardEventSource: src, virtualKey: actionKeyCode, keyDown: false)
         
        record.forEach { (withShift: Bool, code: UInt16) in
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
            
            postSynthetic(actionUp, flags: [], loc)
            postSynthetic(eventDown, flags: withShift ? .maskShift : [], loc)
            postSynthetic(eventUp, flags: withShift ? .maskShift : [], loc)
        }
    }

    // Tags events we post so the global monitor can ignore them — the replacement must not
    // re-enter the record or the action key logic (a fast second Option tap used to interleave)
    private static let syntheticEventMarker: Int64 = 0x0BAB_B1E5

    // Flags are always set explicitly: otherwise a physically held Option leaks into the
    // retyped keys (œ∑† instead of qwt) and turns Delete into Option+Delete (delete word)
    private static func postSynthetic(_ event: CGEvent?, flags: CGEventFlags, _ loc: CGEventTapLocation) {
        guard let event else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: loc)
    }

    static func isSynthetic(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
    }

    
    
    static func replaceTypedText(_ record: [(withShift: Bool, code: UInt16)]) async {
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap
                
        replaceLog("replace: delete \(record.count) chars")
        deleteTypedText(src, loc, record)
        
        try? await Task.sleep(nanoseconds: keyboardDelay)
        
         
        replaceLog("replace: retype codes \(record.map { ($0.withShift ? "⇧" : "") + String($0.code) })")
        typeRecordedText(record, src, loc)
        replaceLog("replace: done")
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
        postSynthetic(eventDown, flags: .maskCommand, loc)
        postSynthetic(eventUp, flags: [], loc)
        
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

    static func typeText(_ text: String) {
        let tranlatedText = translateText(text)
        
        let utf16Chars = Array(tranlatedText.utf16)
        let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true);
        event1?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        postSynthetic(event1, flags: .maskNonCoalesced, .cghidEventTap)

        let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false);
        postSynthetic(event2, flags: .maskNonCoalesced, .cghidEventTap)
    }
}
