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
    print("Keyboard event tests passed")
  }
}
