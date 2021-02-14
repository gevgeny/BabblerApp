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
//
//        let cmdd = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: true)
//        let cmdu = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: false)
//        let spcd = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: true)
//        let spcu = CGEvent(keyboardEventSource: src, virtualKey: 0x31, keyDown: false)
//
//        //spcd?.flags = CGEventFlags.maskCommand;
//
//        let loc = CGEventTapLocation.cghidEventTap
//
//        cmdd?.post(tap: loc)
//        spcd?.post(tap: loc)
//        spcu?.post(tap: loc)
//        cmdu?.post(tap: loc)
    }
}

