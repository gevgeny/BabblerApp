import Cocoa

@main
struct KeyboardUtilsTests {
  static func main() {
    let source = CGEventSource(stateID: .privateState)
    let cases: [(NSEvent.ModifierFlags, CGEventFlags)] = [
      ([], []), (.shift, .maskShift), (.capsLock, .maskAlphaShift),
      ([.shift, .capsLock], [.maskShift, .maskAlphaShift]),
      ([.option, .command, .function], [])
    ]
    for (flags, expected) in cases {
      let events = KeyboardUtils.recordedKeyEvents(RecordedKey(code: Key.a, flags: flags), source: source)
      assert(events.count == 2)
      assert(events.allSatisfy { KeyboardUtils.isSynthetic(NSEvent(cgEvent: $0)!) })
      assert(events[0].type == .keyDown && events[1].type == .keyUp)
      assert(events.allSatisfy { $0.flags == expected })
      assert(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == Int64(Key.a) })
    }
    let mixed = [RecordedKey(code: Key.h, flags: .shift), RecordedKey(code: Key.i, flags: [])]
    let events = mixed.flatMap { KeyboardUtils.recordedKeyEvents($0, source: source) }
    assert(events.map(\.flags) == [.maskShift, .maskShift, [], []])
    let delete = KeyboardUtils.recordedKeyEvents(RecordedKey(code: Key.delete, flags: []), source: source)
    assert(delete.allSatisfy { $0.flags.isEmpty })
    let globeDown = GlobeKeyMonitor.modifierEvent(isDown: true, flags: [.maskShift, .maskAlphaShift])!
    assert(globeDown.type == .flagsChanged && globeDown.keyCode == Key.function)
    assert(globeDown.modifierFlags.contains([.function, .shift, .capsLock]))
    let globeUp = GlobeKeyMonitor.modifierEvent(isDown: false, flags: [.maskSecondaryFn, .maskShift])!
    assert(globeUp.type == .flagsChanged && globeUp.keyCode == Key.function)
    assert(!globeUp.modifierFlags.contains(.function) && globeUp.modifierFlags.contains(.shift))
    // Filtering event metadata must preserve real modifiers and Fn shortcuts.
    let keyboardModifiers: [CGEventFlags] = [.maskAlphaShift, .maskShift, .maskControl,
      .maskAlternate, .maskCommand, .maskNumericPad, .maskHelp]
    for modifier in keyboardModifiers {
      let event = GlobeKeyMonitor.modifierEvent(isDown: true,
        flags: [modifier, CGEventFlags(rawValue: 0x2000_0000), .maskNonCoalesced])!
      assert(event.cgEvent?.flags == [modifier, .maskSecondaryFn])
    }
    // A configured Mac should show no setup warnings. Missing permissions must
    // not be mistaken for a missing keyboard, and system actions need guidance.
    func setup(_ accessibility: Bool = true, _ inputMonitoring: Bool = true,
               action: Int? = 0, available: Bool = true) -> [String] {
      KeyboardUtils.globeSetupInstructions(accessibilityGranted: accessibility,
        inputMonitoringGranted: inputMonitoring, systemAction: action, listenerAvailable: available)
    }
    assert(setup().isEmpty)
    assert(setup(false, false, available: false).count == 2)
    assert(setup(true, false, available: false).first?.contains("Input Monitoring") == true)
    assert(setup(false).count == 1)
    for action in [1, 2, 3] {
      assert(setup(action: action).first?.contains("Do Nothing") == true)
    }
    assert(setup(action: nil).count == 1)
    assert(setup(available: false).first?.contains("Apple keyboard") == true)
    print("Keyboard event tests passed")
  }
}
