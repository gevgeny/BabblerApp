import Foundation
import Cocoa

let keyboardDelay = UInt64(50_000_000)

@objc class KeyboardUtils: NSObject {
    static private var actionKeyCode = CGKeyCode(58);
    
    static private var actionKeyFlag: NSEvent.ModifierFlags = .option;
    
    static private var isActionKeyPressed = false;
    
    static func addGlobalEventListener(_ callback: @escaping (NSEvent) -> Void) -> Void {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .flagsChanged]) {
            callback($0);
        };
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
                
        deleteLastTypedWord(src, loc)
        
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
            
            let newClipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            
            // Put old text into clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboardText, forType: .string);
            
            callback(newClipboardText);
        }
    }
    
    static func translateText(_ text: String) -> String {
        let tranlatedText = text.map{char -> String in
            if (ruEnDictionary[String(char)] != nil) {
                return ruEnDictionary[String(char)]!
            } else if (enRuDictionary[String(char)] != nil){
                return enRuDictionary[String(char)]!
            } else {
                return String(char);
            }
        }
        return tranlatedText.joined();
    }

    static func typeText(_ text: String) {
        let tranlatedText = translateText(text)
        
        let utf16Chars = Array(tranlatedText.utf16)
        let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true);
        event1?.flags = .maskNonCoalesced
        event1?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        event1?.post(tap: .cghidEventTap)

        let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false);
        event2?.flags = .maskNonCoalesced
        event2?.post(tap: .cghidEventTap)
    }
}
