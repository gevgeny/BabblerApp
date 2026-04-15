import Foundation
import Cocoa

let keyboardDelay = UInt64(50_000_000)

@objc class KeyboardUtils: NSObject {
    static private(set) var actionKeyCode = CGKeyCode(58);
    
    static private(set) var actionKeyFlag: NSEvent.ModifierFlags = .option;
    
    static private var isActionKeyPressed = false;
    
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
  
    static func checkActionKeyPress(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        if (flags == actionKeyFlag && code == actionKeyCode) {
            isActionKeyPressed = true;
            return false
        } else if (code == actionKeyCode && isActionKeyPressed) {
            isActionKeyPressed = false
            return true
        } else {				        
            isActionKeyPressed = false
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

            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
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
            
            if withShift {
                eventDown?.flags = CGEventFlags.maskShift;
            }
            actionUp?.post(tap: loc)
            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
        }
    }

    
    
    static func replaceTypedText(_ record: [(withShift: Bool, code: UInt16)]) async {
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap
                
        deleteTypedText(src, loc, record)
        
        try? await Task.sleep(nanoseconds: keyboardDelay)
        
         
        typeRecordedText(record, src, loc)
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
    
    // sourceId: the layout ID that was active when the text was originally typed/selected.
    // Required to pick the right Cyrillic↔Latin dictionary when converting away from Cyrillic.
    static func translateText(_ text: String, sourceId: String?) -> String {
        guard let targetSource = LanguageUtils.getCurrentInputSource() else { return text }

        let mapper: [String: String]
        if LanguageUtils.isCyrillic(targetSource) {
            // Switching TO Cyrillic — map Latin → Cyrillic using the target layout's dict
            mapper = latinToCyrillicDict(for: targetSource.id)
        } else {
            // Switching TO Latin — map Cyrillic → Latin using the source layout's dict
            let srcId = sourceId ?? LanguageUtils.cyrillicInputSource?.id ?? ""
            mapper = cyrillicToLatinDict(for: srcId)
        }

        return text.map { ch -> String in
            let s = String(ch)
            return mapper[s] ?? s
        }.joined()
    }

    static func typeText(_ text: String, sourceId: String? = nil) {
        let translatedText = translateText(text, sourceId: sourceId)

        let utf16Chars = Array(translatedText.utf16)
        let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true)
        event1?.flags = .maskNonCoalesced
        event1?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        event1?.post(tap: .cghidEventTap)

        let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false)
        event2?.flags = .maskNonCoalesced
        event2?.post(tap: .cghidEventTap)
    }
}

