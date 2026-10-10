import Cocoa

@main
struct ActionKeyTests {
  static func main() {
    var tracker = KeyboardUtils.ActionKeyTracker()
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags, count: UInt32 = 0,
               enabled: Bool = true) -> KeyboardUtils.ActionKeyResult {
      tracker.check(code, flags, primaryCode: Key.option, primaryFlag: .option,
                    globeEnabled: enabled, keyDownCount: count)
    }
    assert(event(Key.option, .option) == .none)
    assert(event(Key.option, []) == .action)
    assert(event(Key.function, .function) == .none)
    assert(event(Key.function, []) == .action)
    assert(event(Key.function, [.function, .shift]) == .none)
    assert(event(Key.shift, .function) == .none)
    assert(event(Key.function, []) == .lineAction)
    assert(event(Key.option, [.option, .shift]) == .none)
    assert(event(Key.option, .shift) == .lineAction)
    assert(event(Key.function, .function, enabled: false) == .none)
    assert(event(Key.function, [], enabled: false) == .none)
    assert(event(Key.function, .function) == .none)
    assert(event(Key.leftArrow, [.function, .numericPad], count: 1) == .none)
    assert(event(Key.function, [], count: 1) == .none)
    // Secure input hides keyDown events, but the system counter still changes.
    assert(event(Key.function, .function, count: 1) == .none)
    assert(event(Key.function, [], count: 2) == .none)
    assert(event(Key.option, [.option, .command]) == .none)
    assert(event(Key.option, .command) == .none)
    assert(event(Key.function, .function) == .none)
    assert(event(Key.option, [.option, .function]) == .none)
    assert(event(Key.option, .function) == .none)
    assert(event(Key.function, []) == .none)
    assert(event(Key.option, [.option, .capsLock]) == .none)
    assert(event(Key.option, .capsLock) == .action)
    var rightControl = KeyboardUtils.ActionKeyTracker()
    assert(rightControl.check(Key.rightControl, .control, primaryCode: Key.rightControl,
                              primaryFlag: .control, globeEnabled: true, keyDownCount: 0) == .none)
    assert(rightControl.check(Key.rightControl, [], primaryCode: Key.rightControl,
                              primaryFlag: .control, globeEnabled: true, keyDownCount: 0) == .action)

    // Replay the extra session flag observed after a language switch on macOS.
    // Non-modifier event flags must not prevent following Globe taps.
    let systemEventFlags = CGEventFlags(rawValue: 0x2000_0000 | CGEventFlags.maskNonCoalesced.rawValue)
    var globeAfterReplacement = KeyboardUtils.ActionKeyTracker()
    for tap in 0..<6 {
      let shift: CGEventFlags = tap.isMultiple(of: 2) ? [] : .maskShift
      let down = GlobeKeyMonitor.modifierEvent(isDown: true,
        flags: [shift, systemEventFlags])!
      let up = GlobeKeyMonitor.modifierEvent(isDown: false,
        flags: [shift, .maskSecondaryFn])!
      assert(globeAfterReplacement.check(down.keyCode, down.modifierFlags,
        primaryCode: Key.option, primaryFlag: .option, globeEnabled: true,
        keyDownCount: UInt32(tap)) == .none)
      assert(globeAfterReplacement.check(up.keyCode, up.modifierFlags,
        primaryCode: Key.option, primaryFlag: .option, globeEnabled: true,
        keyDownCount: UInt32(tap)) == (shift.isEmpty ? .action : .lineAction))
    }
    print("Action key tests passed")
  }
}
