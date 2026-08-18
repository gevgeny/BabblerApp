import Foundation

/// Decides whether a word that was just typed should be rewritten in the other
/// keyboard layout.
///
/// The rule is deliberately conservative: it only fires when the typed text is
/// *not* a word in the current layout and *is* a word in the other one. A false
/// positive mangles correct text and is far more annoying than a missed
/// correction, so anything ambiguous is left alone.
enum AutoSwitchEngine {

  enum Decision: Equatable {
    case keep
    case switchLayout
  }

  /// Characters that never form part of a word in either layout, so seeing one
  /// means this is an identifier, email, URL, path or code — not prose.
  ///
  /// Note what is deliberately *absent*: `, . ; ' [ ]` and backtick. Those are
  /// produced by the keys carrying б ю ж э х ъ, so a Russian word typed on the
  /// English layout is full of them — "rjvgm.nth" is "компьютер". Rejecting them
  /// here would blind the engine to the most common case it exists to fix.
  private static let disqualifyingCharacters = CharacterSet(
    charactersIn: "@/\\_+-=#$%^&*(){}|:\"<>~"
  )

  /// Punctuation safe to strip from the ends of a word. Excludes the
  /// layout-bearing characters above, so a word starting with б or ending in ю
  /// survives intact.
  private static let trimmableCharacters = CharacterSet(charactersIn: "!?()\"«»…—")

  static func evaluate(
    word rawWord: String,
    currentLayout: Layout,
    dictionary: LayoutDictionary = .shared
  ) -> Decision {
    guard dictionary.isReady else { return .keep }

    let trimmed = rawWord.trimmingCharacters(in: trimmableCharacters)
    guard isEligible(trimmed) else { return .keep }

    let word = trimmed.lowercased()

    // Already a real word where it stands — leave it alone.
    if dictionary.contains(word, in: currentLayout) { return .keep }

    let converted = convert(word, to: currentLayout.other)
    guard converted != word else { return .keep }

    // The candidate must be a plain run of letters in the target layout.
    // Anything else means these keys do not spell a word over there.
    guard converted.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil else {
      return .keep
    }

    return dictionary.contains(converted, in: currentLayout.other) ? .switchLayout : .keep
  }

  /// Lowercased, edge-punctuation-free form used as the identity of a word for
  /// the undo and ignore lists.
  static func normalize(_ word: String) -> String {
    word.trimmingCharacters(in: trimmableCharacters).lowercased()
  }

  /// Maps every character to the other layout using the existing keyboard maps.
  static func convert(_ text: String, to target: Layout) -> String {
    let mapper = target == .russian ? enRuDictionary : ruEnDictionary
    return text.map { mapper[String($0)] ?? String($0) }.joined()
  }

  private static func isEligible(_ word: String) -> Bool {
    // Too short to judge: "ok", "hi", "и", "не".
    if word.count < 3 { return false }

    // Digits mean an identifier, a version, a password.
    if word.rangeOfCharacter(from: .decimalDigits) != nil { return false }

    if word.rangeOfCharacter(from: disqualifyingCharacters) != nil { return false }

    // Proper nouns and acronyms are often missing from the word lists, and
    // rewriting a name is very visible. Any capital disqualifies.
    if word != word.lowercased() { return false }

    return true
  }
}
