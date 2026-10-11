import Foundation
import Cocoa
import os
import IOKit.hid
import IOKit.hidsystem

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

struct RecordedKey {
  let code: UInt16
  let modifiers: CGEventFlags

  init(code: UInt16, flags: NSEvent.ModifierFlags) {
    self.code = code
    var modifiers: CGEventFlags = []
    if flags.contains(.shift) { modifiers.insert(.maskShift) }
    if flags.contains(.capsLock) { modifiers.insert(.maskAlphaShift) }
    self.modifiers = modifiers
  }
}

// Read only Apple's Fn / Globe HID elements. macOS can suppress the regular
// modifier event entirely when "Press Globe key to" is set to "Do Nothing".
final class GlobeKeyMonitor {
  private var manager: IOHIDManager?
  private(set) var isPressed = false
  private let callback: (NSEvent) -> Void
  private let matches: [[String: Int]] = [
    [kIOHIDElementUsagePageKey: 0xFF, kIOHIDElementUsageKey: 0x03],
    [kIOHIDElementUsagePageKey: 0xFF01, kIOHIDElementUsageKey: 0x03]
  ]

  init(callback: @escaping (NSEvent) -> Void) { self.callback = callback }

  func start() -> Bool {
    if manager != nil { return true }
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let keyboardMatch = [kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
                         kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard)]
    let vendorMatches = matches.map { match in
      [kIOHIDDeviceUsagePageKey: match[kIOHIDElementUsagePageKey]!,
       kIOHIDDeviceUsageKey: match[kIOHIDElementUsageKey]!]
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, ([keyboardMatch] + vendorMatches) as CFArray)
    IOHIDManagerSetInputValueMatchingMultiple(manager, matches as CFArray)
    IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
      guard result == kIOReturnSuccess, let context else { return }
      let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(context).takeUnretainedValue()
      monitor.handle(isDown: IOHIDValueGetIntegerValue(value) != 0)
    }, Unmanaged.passUnretained(self).toOpaque())
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      NSLog("Babbler Globe keyboard monitor could not open: 0x%08X", result)
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      return false
    }
    self.manager = manager
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    let hasGlobe = devices.contains { device in
      matches.contains { match in
        let elements = IOHIDDeviceCopyMatchingElements(device, match as CFDictionary,
                                                       IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]
        return !(elements?.isEmpty ?? true)
      }
    }
    guard hasGlobe else {
      NSLog("Babbler Globe keyboard monitor found no Apple Globe key")
      stop()
      return false
    }
    return true
  }

  private func handle(isDown: Bool) {
    guard isPressed != isDown else { return }
    isPressed = isDown
    // Deliver a modifier event directly to Babbler without posting a synthetic
    // event into other apps. Preserve Shift for whole-line conversion.
    if let event = Self.modifierEvent(isDown: isDown, flags: CGEventSource.flagsState(.combinedSessionState)) {
      callback(event)
    }
  }

  static func modifierEvent(isDown: Bool, flags: CGEventFlags) -> NSEvent? {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: Key.function, keyDown: isDown) else { return nil }
    event.type = .flagsChanged
    // Session flags also contain event metadata. Only keyboard modifiers belong
    // in the Fn event; otherwise an extra system bit can reject the next tap.
    let keyboardModifiers: CGEventFlags = [.maskAlphaShift, .maskShift, .maskControl,
      .maskAlternate, .maskCommand, .maskNumericPad, .maskHelp, .maskSecondaryFn]
    var flags = flags.intersection(keyboardModifiers)
    if isDown { flags.insert(.maskSecondaryFn) } else { flags.remove(.maskSecondaryFn) }
    event.flags = flags
    return NSEvent(cgEvent: event)
  }

  func stop() {
    guard let manager else { return }
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    self.manager = nil
    isPressed = false
  }

  deinit { stop() }
}

@objc class KeyboardUtils: NSObject {
    static private(set) var actionKeyCode = CGKeyCode(58);
    
    static private(set) var actionKeyFlag: NSEvent.ModifierFlags = .option;
    
    enum ActionKeyResult {
        case none
        case action        // switch language; optionally convert the word or selection
        case lineAction    // switch language; optionally convert the line or selection
    }

    struct ActionKeyTracker {
      private var pressedCode: UInt16?
      private var pressedFlag: NSEvent.ModifierFlags = []
      private var withShift = false
      private var interrupted = false
      private var keyDownCountAtPress: UInt32 = 0

      mutating func check(_ code: UInt16, _ flags: NSEvent.ModifierFlags,
                          primaryCode: UInt16, primaryFlag: NSEvent.ModifierFlags,
                          globeEnabled: Bool, keyDownCount: UInt32) -> ActionKeyResult {
        if let pressedCode {
          if code == pressedCode && !flags.contains(pressedFlag) {
            let result: ActionKeyResult = interrupted || keyDownCount != keyDownCountAtPress
              ? .none : (withShift ? .lineAction : .action)
            self = ActionKeyTracker()
            return result
          }
          // Shift may be released before the action key. Preserve the line action.
          if flags.contains(.shift) { withShift = true }
          let allowed: NSEvent.ModifierFlags = [pressedFlag, .shift, .capsLock, .numericPad]
          if !flags.subtracting(allowed).isEmpty || !KeyboardUtils.isModifierKey(code) {
            interrupted = true
          }
          return .none
        }

        let triggerFlag: NSEvent.ModifierFlags
        if code == primaryCode {
          triggerFlag = primaryFlag
        } else if globeEnabled && code == Key.function {
          triggerFlag = .function
        } else {
          return .none
        }
        let allowed: NSEvent.ModifierFlags = [triggerFlag, .shift, .capsLock, .numericPad]
        guard flags.contains(triggerFlag), flags.subtracting(allowed).isEmpty else { return .none }
        pressedCode = code
        pressedFlag = triggerFlag
        withShift = flags.contains(.shift)
        interrupted = false
        keyDownCountAtPress = keyDownCount
        return .none
      }
    }

    static private var actionKeyTracker = ActionKeyTracker()
    static private var globeMonitor: GlobeKeyMonitor?
    static private var globeCallback: ((NSEvent) -> Void)?
    static private var globalMonitor: Any?

    static func setActionKey(code: UInt16) {
        actionKeyTracker = ActionKeyTracker()
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
    
    static var isGlobeKeyHeld: Bool { globeMonitor?.isPressed == true }

    static var hasInputMonitoringPermission: Bool {
      IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static var systemGlobeAction: Int? {
      let domain = "com.apple.HIToolbox" as CFString
      // Refresh after returning from System Settings. Never change the system preference.
      CFPreferencesAppSynchronize(domain)
      return CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? Int
    }

    static func globeSetupInstructions(accessibilityGranted: Bool, inputMonitoringGranted: Bool,
                                       systemAction: Int?, listenerAvailable: Bool) -> [String] {
      var instructions: [String] = []
      if !accessibilityGranted {
        instructions.append("Allow Babbler in Privacy & Security → Accessibility, then restart Babbler.")
      }
      if !inputMonitoringGranted {
        instructions.append("Allow Babbler in Privacy & Security → Input Monitoring, then restart Babbler.")
      }
      if systemAction != 0 {
        instructions.append("In System Settings → Keyboard, set ‘Press Globe key to’ to ‘Do Nothing’.")
      }
      if accessibilityGranted && inputMonitoringGranted && !listenerAvailable {
        instructions.append("Connect an Apple keyboard and restart Babbler to enable Globe.")
      }
      return instructions
    }

    @discardableResult
    static func addGlobalEventListener(_ callback: @escaping (NSEvent) -> Void) -> Bool {
      if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
      globalMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.keyDown, .keyUp, .leftMouseDown, .flagsChanged]
      ) { event in
        // HID supplies both Globe transitions. Do not also handle a regular
        // Fn event on systems that still emit one.
        DispatchQueue.main.async {
          if event.type == .flagsChanged && event.keyCode == Key.function
              && globeMonitor != nil && UserDefaults.standard.bool(forKey: globeActionKeyEnabledKey) {
            return
          }
          callback(event)
        }
      }
      globeCallback = callback
      return updateGlobeKeyMonitoring()
    }

    static func updateGlobeKeyMonitoring() -> Bool {
      actionKeyTracker = ActionKeyTracker()
      guard UserDefaults.standard.bool(forKey: globeActionKeyEnabledKey), let callback = globeCallback else {
        globeMonitor?.stop()
        globeMonitor = nil
        return false
      }
      if globeMonitor != nil { return true }
      let monitor = GlobeKeyMonitor(callback: callback)
      guard monitor.start() else { return false }
      globeMonitor = monitor
      return true
    }

    static func checkActionKeyPress(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> ActionKeyResult {
      actionKeyTracker.check(code, flags, primaryCode: actionKeyCode, primaryFlag: actionKeyFlag,
                             globeEnabled: UserDefaults.standard.bool(forKey: globeActionKeyEnabledKey),
                             keyDownCount: keyDownCount())
    }

    private static func keyDownCount() -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }

    private static func isModifierKey(_ code: UInt16) -> Bool {
        switch code {
        case Key.shift, Key.rightShift, Key.option, Key.rightOption,
             Key.control, Key.rightControl, Key.command, Key.rightCommand, Key.capsLock, Key.function:
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
    
    static func recordedKeyEvents(_ key: RecordedKey, source: CGEventSource?) -> [CGEvent] {
      let events = [
        CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: true),
        CGEvent(keyboardEventSource: source, virtualKey: key.code, keyDown: false)
      ].compactMap { $0 }
      // CGEvent initially inherits live modifiers. Shift used to trigger a line
      // conversion must not turn the replacement into uppercase or a selection.
      for event in events {
        event.flags = key.modifiers
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
      }
      return events
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

    
    
    @MainActor
    static func replaceTypedText(_ record: [RecordedKey]) async {
      guard !record.isEmpty else { return }
      let source = CGEventSource(stateID: .privateState)
      let location = CGEventTapLocation.cghidEventTap
      let delete = RecordedKey(code: Key.delete, flags: [])
      replaceLog("replace: delete \(record.count) chars")
      for _ in record {
        for event in recordedKeyEvents(delete, source: source) { event.post(tap: location) }
      }
      try? await Task.sleep(nanoseconds: keyboardDelay)
      replaceLog("replace: retype codes \(record.map { $0.code })")
      for key in record {
        for event in recordedKeyEvents(key, source: source) { event.post(tap: location) }
      }
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
        
        // All NSPasteboard access and the callback must run on the main thread.
        // NSPasteboard (like all AppKit objects) is not thread-safe, and the
        // downstream callback calls Carbon TIS APIs which also require the main thread.
        Task { @MainActor in
            // The app copies asynchronously, so a fixed delay was too short for slow apps and
            // made the swap silently do nothing. We cleared the clipboard above, so any string
            // appearing now is the copied selection; give up after ~300 ms (nothing selected).
            var newClipboardText = ""
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if let copied = NSPasteboard.general.string(forType: .string) {
                    newClipboardText = copied
                    break
                }
            }

            // Restore old clipboard contents
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboardText, forType: .string)

            callback(newClipboardText)
        }
    }
    
    // Direction comes from the text itself, not the current layout: a selection may have been
    // typed any time in either layout (selecting Russian text while EN was active used to
    // "convert" it to the same text). The first letter decides: Cyrillic → to English,
    // Latin → to Russian. Only text without letters falls back to the layout.
    static func translateText(_ text: String) -> (text: String, toRussian: Bool) {
        let firstLetter = text.unicodeScalars.first {
            (0x0400...0x04FF).contains($0.value) || ($0.isASCII && $0.properties.isAlphabetic)
        }
        let targetIsRussian = firstLetter.map { $0.isASCII }
            ?? InputSourceUtils.isRussian(InputSourceUtils.getCurrentInputSource())
        let mapper = targetIsRussian ? enRuDictionary : ruEnDictionary

        let translated = text.map { ch -> String in
            let s = String(ch)
            if let mapped = mapper[s] {
                return mapped
            } else {
                return s
            }
        }
        return (translated.joined(), targetIsRussian)
    }

    static func typeText(_ text: String) {
        let (tranlatedText, toRussian) = translateText(text)
        
        let utf16Chars = Array(tranlatedText.utf16)
        let event1 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: true);
        event1?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        postSynthetic(event1, flags: .maskNonCoalesced, .cghidEventTap)

        let event2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x31, keyDown: false);
        postSynthetic(event2, flags: .maskNonCoalesced, .cghidEventTap)

        // Leave the layout matching the converted text (the action key toggled it blindly)
        InputSourceUtils.selectLang(russian: toRussian)
    }
}
