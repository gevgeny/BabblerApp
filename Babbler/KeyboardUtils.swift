import Foundation
import Cocoa

@objc class KeyboardUtils: NSObject {
    
    static private var isOptionPressed = false;
    
    static func addGlobalEventListener(_ callback: @escaping (NSEvent) -> Void) -> Void {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .flagsChanged]) {
            callback($0);
        };
    }
    
    static func checkActionKeyPress(_ code: UInt16, _ withOption: Bool) -> Bool {
        if (withOption && code == Key.option) {
            isOptionPressed = true;
            return false
        } else if (code == Key.option && isOptionPressed) {
            isOptionPressed = false
            return true
        } else {				        
            isOptionPressed = false
            return false
        }
    }
    
    static func replaceTypedText(_ record: [(withShift: Bool, code: UInt16)]) {
        let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let loc = CGEventTapLocation.cghidEventTap
        
        // Delete last typed text
        for _ in 1...record.count {
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: Key.delete, keyDown: false)
            
            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
        }
        
        // Type new text
        record.forEach { (withShift: Bool, code: UInt16) in
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
            
            if withShift {
                eventDown?.flags = CGEventFlags.maskShift;
            }
            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
        }
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
        
        // Wait till text copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Get new text from clipboard
            let newClipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            
            // Put old text into clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboardText, forType: .string);
            
            callback(newClipboardText);
        }
    }
    
    static func typeText(_ text: String) {
        text.forEach { char in
            let code = Array(String(char).utf16)[0]
            let src = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
            let loc = CGEventTapLocation.cghidEventTap
            let eventDown = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
            let eventUp = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
            
//            if withShift {
//                eventDown?.flags = CGEventFlags.maskShift;
//            }
            eventDown?.post(tap: loc)
            eventUp?.post(tap: loc)
        }
    }
}

