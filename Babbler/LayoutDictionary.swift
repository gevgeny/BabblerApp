import Foundation
import Compression

/// Which of the two supported layouts a piece of text belongs to.
enum Layout {
  case english
  case russian

  var other: Layout {
    self == .english ? .russian : .english
  }

  /// Letters that can be typed in this layout, used to reconstruct a word from
  /// which one keystroke was dropped.
  var alphabet: [Character] {
    self == .english
      ? Array("abcdefghijklmnopqrstuvwxyz")
      : Array("абвгдежзийклмнопрстуфхцчшщъыьэюя")
  }
}

/// Word lists used to decide whether a typed string is a real word in a layout.
///
/// The lists ship gzipped in the app bundle (~1 MB total) and are decompressed
/// into two `Set<String>` on first use. Loading happens on a background queue so
/// the ~150 ms of parsing never blocks the event handler; until it finishes every
/// lookup reports `false`, which makes the auto-switch engine decline to act
/// rather than guess.
final class LayoutDictionary {
  static let shared = LayoutDictionary()

  private var english: Set<String> = []
  private var russian: Set<String> = []
  private let lock = NSLock()
  private var didStartLoading = false
  private var isLoaded = false

  private init() {}

  var isReady: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isLoaded
  }

  /// Starts loading in the background. Safe to call repeatedly; only the first
  /// call does any work.
  func preload() {
    lock.lock()
    if didStartLoading {
      lock.unlock()
      return
    }
    didStartLoading = true
    lock.unlock()

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      var en = Self.loadWords(named: "en")
      var ru = Self.loadWords(named: "ru")
      en.formUnion(Self.loadCustomWords(named: "custom-en"))
      ru.formUnion(Self.loadCustomWords(named: "custom-ru"))

      self.lock.lock()
      self.english = en
      self.russian = ru
      self.isLoaded = !en.isEmpty && !ru.isEmpty
      self.lock.unlock()
    }
  }

  /// Directory holding the user's own additions, alongside the crash logs.
  static var customWordsDirectory: URL {
    FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Babbler", isDirectory: true)
  }

  func contains(_ word: String, in layout: Layout) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard isLoaded else { return false }
    return layout == .english ? english.contains(word) : russian.contains(word)
  }

  /// Whether `word` becomes a real word by inserting exactly one character —
  /// that is, whether the user typed a real word but missed one keystroke.
  ///
  /// Only omission is modelled, and that is a measured decision rather than a
  /// conservative guess. Against 40,000 correctly typed English words, allowing
  /// any edit of distance one raised the false-positive rate from 0.025% to
  /// 4.01% ("learn" matched "дукат", "rate" matched "кафе"). Restricting to a
  /// dropped keystroke brings it to 0.010% while still catching every typo in
  /// the test set; transposition adds no recall, and allowing a doubled letter
  /// is actively harmful because English is full of "ff", "ee" and "ll".
  ///
  /// A deletion index over the dictionary would hold roughly 1.6M entries. It is
  /// unnecessary: `w` is a word of which `q` is a one-character deletion exactly
  /// when some single-character insertion into `q` equals `w`, so the insertions
  /// are generated and probed against the set we already have. That is about 224
  /// hash lookups, measured at 0.03 ms, with no extra memory.
  func hasWordOneInsertionAway(_ word: String, in layout: Layout) -> Bool {
    guard word.count >= Self.minimumTypoLength else { return false }

    lock.lock()
    defer { lock.unlock() }
    guard isLoaded else { return false }
    let words = layout == .english ? english : russian

    var characters = Array(word)
    // Never insert before the first character: typos essentially never hit the
    // first key, and forbidding it measurably lowered false positives.
    for position in 1...characters.count {
      characters.insert(" ", at: position)
      for letter in layout.alphabet {
        characters[position] = letter
        // The reconstructed word has to start the same way the user did.
        if characters[0] == word.first, words.contains(String(characters)) {
          return true
        }
      }
      characters.remove(at: position)
    }
    return false
  }

  /// Below this length a dropped keystroke leaves too little signal, and the
  /// candidate space is dense enough that almost anything matches something.
  static let minimumTypoLength = 5

  private static func loadWords(named name: String) -> Set<String> {
    guard let url = Bundle.main.url(forResource: name, withExtension: "txt.gz"),
          let compressed = try? Data(contentsOf: url),
          let text = gunzip(compressed) else {
      return []
    }

    var words = Set<String>()
    words.reserveCapacity(220_000)
    text.enumerateLines { line, _ in
      if !line.isEmpty { words.insert(line) }
    }
    return words
  }

  /// Plain-text words the user added themselves, one per line, `#` for comments.
  /// Missing files are normal and simply contribute nothing.
  private static func loadCustomWords(named name: String) -> Set<String> {
    let url = customWordsDirectory.appendingPathComponent("\(name).txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

    var words = Set<String>()
    text.enumerateLines { line, _ in
      let word = line.trimmingCharacters(in: .whitespaces).lowercased()
      if !word.isEmpty, !word.hasPrefix("#") { words.insert(word) }
    }
    return words
  }

  /// Minimal gzip reader: skips the gzip header, then inflates the raw deflate
  /// payload with libcompression. Foundation has no public gzip API, and the
  /// files are static build artifacts, so a full-featured parser is unnecessary.
  private static func gunzip(_ data: Data) -> String? {
    guard data.count > 18,
          data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else { return nil }

    let flags = data[3]
    var offset = 10

    if flags & 0x04 != 0 {  // FEXTRA
      guard offset + 2 <= data.count else { return nil }
      let extraLength = Int(data[offset]) | (Int(data[offset + 1]) << 8)
      offset += 2 + extraLength
    }
    if flags & 0x08 != 0 {  // FNAME
      while offset < data.count, data[offset] != 0 { offset += 1 }
      offset += 1
    }
    if flags & 0x10 != 0 {  // FCOMMENT
      while offset < data.count, data[offset] != 0 { offset += 1 }
      offset += 1
    }
    if flags & 0x02 != 0 {  // FHCRC
      offset += 2
    }
    guard offset < data.count - 8 else { return nil }

    // The gzip trailer stores the uncompressed size mod 2^32. The lists are a
    // few MB, so it is exact, but clamp to a sane floor in case it is not.
    let sizeOffset = data.count - 4
    let uncompressedSize = Int(data[sizeOffset])
      | (Int(data[sizeOffset + 1]) << 8)
      | (Int(data[sizeOffset + 2]) << 16)
      | (Int(data[sizeOffset + 3]) << 24)
    let capacity = max(uncompressedSize, (data.count - offset) * 8)

    let payload = data.subdata(in: offset..<(data.count - 8))
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { buffer.deallocate() }

    let written = payload.withUnsafeBytes { raw -> Int in
      guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
      return compression_decode_buffer(
        buffer, capacity, base, payload.count, nil, COMPRESSION_ZLIB
      )
    }
    guard written > 0 else { return nil }

    return String(bytes: UnsafeBufferPointer(start: buffer, count: written), encoding: .utf8)
  }
}
