import Foundation

// Regression harness for the auto-switch tokenizer and engine.
//
// The bug this exists to prevent: every earlier test called
// AutoSwitchEngine.evaluate directly with whole words, which bypassed the
// tokenizer in AppDelegate entirely. The engine was always correct; the code
// splitting text into words in front of it was not. ",bpytc" (бизнес) was cut
// at the leading comma, because on the English layout "," is б.
//
// So this harness models the tokenizer as well as the engine.

let resources = ProcessInfo.processInfo.environment["BABBLER_RESOURCES"]
  ?? FileManager.default.currentDirectoryPath + "/Babbler/Resources"

func loadWords(_ name: String) -> [String] {
  let url = URL(fileURLWithPath: "\(resources)/\(name).txt.gz")
  let data = try! Data(contentsOf: url)
  var words: [String] = []
  LayoutDictionary.testGunzip(data)!.enumerateLines { line, _ in
    if !line.isEmpty { words.append(line) }
  }
  return words
}

let englishWords = loadWords("en")
let russianWords = loadWords("ru")
LayoutDictionary.shared.setForTests(Set(englishWords), Set(russianWords))

var failures = 0
func check(_ passed: Bool, _ message: String) {
  if !passed {
    failures += 1
    print("  FAIL  \(message)")
  }
}

// MARK: - Tokenizer

/// Mirrors AppDelegate.wordTerminator(for:). Only layout-independent keys end a
/// word. Punctuation must not: on the English layout "," is б, "." is ю, ";" is
/// ж, so splitting on them cuts Russian words apart.
func isTerminator(_ character: Character) -> Bool {
  character == " " || character == "\t" || character == "\n"
}

/// Splits a raw keystroke stream the way AppDelegate accumulates it.
func tokenize(_ typed: String) -> [String] {
  var words: [String] = []
  var current = ""
  for character in typed {
    if isTerminator(character) {
      if !current.isEmpty { words.append(current) }
      current = ""
    } else {
      current.append(character)
    }
  }
  if !current.isEmpty { words.append(current) }
  return words
}

print("=== tokenizer: Russian words must not be split on punctuation keys")
let tokenizerCases: [(typed: String, expected: [String], meaning: String)] = [
  (",bpytc",        [",bpytc"],            "бизнес"),
  ("hf,jnftn",      ["hf,jnftn"],          "работает"),
  ("vj;yj",         ["vj;yj"],             "можно"),
  ("k.,jq",         ["k.,jq"],             "любой"),
  ("j,]trn",        ["j,]trn"],            "объект"),
  ("'njn",          ["'njn"],              "этот"),
  ("[jhjij",        ["[jhjij"],            "хорошо"),
  (",bpytc gkfy",   [",bpytc", "gkfy"],    "бизнес план"),
  ("yt hf,jnftn",   ["yt", "hf,jnftn"],    "не работает"),
]
for testCase in tokenizerCases {
  let produced = tokenize(testCase.typed)
  check(produced == testCase.expected,
        "\(testCase.typed) (\(testCase.meaning)) tokenized as \(produced), expected \(testCase.expected)")
}

print("=== tokenizer: those words then convert to real Russian")
for testCase in tokenizerCases where testCase.expected.count == 1 {
  let converted = AutoSwitchEngine.convert(testCase.typed, to: .russian)
  check(converted == testCase.meaning,
        "\(testCase.typed) converted to \(converted), expected \(testCase.meaning)")
  check(AutoSwitchEngine.evaluate(word: testCase.typed, currentLayout: .english) == .switchLayout,
        "\(testCase.typed) (\(testCase.meaning)) must switch")
}

// MARK: - Trailing punctuation

print("=== trailing punctuation: real words keep their full stop")
for word in ["it.", "at.", "am.", "by.", "bye.", "belt.", "and.", "the.", "is.", "to.", "in.", "on.", "we,", "hello,"] {
  check(AutoSwitchEngine.evaluate(word: word, currentLayout: .english) == .keep,
        "\(word) must be kept")
}

print("=== trailing punctuation: Russian words ending in ю/б/ж still switch")
for word in ["твою", "всю", "даю", "свою", "мою", "тебя", "хочу", "работаю", "думаю", "знаю"] {
  let typed = AutoSwitchEngine.convert(word, to: .english)
  check(AutoSwitchEngine.evaluate(word: typed, currentLayout: .english) == .switchLayout,
        "\(word) typed as \(typed) must switch")
}

// MARK: - Core behaviour

print("=== core corrections")
for (typed, layout) in [("ghbdtn", Layout.english), ("rjvgm.nth", .english), ("hf,jnftn", .english),
                        ("руддщ", .russian), ("сщьзгеук", .russian)] {
  check(AutoSwitchEngine.evaluate(word: typed, currentLayout: layout) == .switchLayout,
        "\(typed) must switch")
}

print("=== rejections")
for (word, layout) in [("ok", Layout.english), ("abc123", .english), ("user@host.com", .english),
                       ("Ghbdtn", .english), ("src/main", .english), ("hello", .english),
                       ("привет", .russian)] {
  check(AutoSwitchEngine.evaluate(word: word, currentLayout: layout) == .keep,
        "\(word) must be kept")
}

print("=== short words: never switched alone, but eligible for a phrase sweep")
for word in ["z", "yt", "b", "ns", "gj"] {
  check(AutoSwitchEngine.evaluate(word: word, currentLayout: .english) == .keep,
        "\(word) alone must be kept")
  check(AutoSwitchEngine.qualifiesForPhraseExtension(word: word, currentLayout: .english),
        "\(word) must qualify for a phrase sweep")
}
for word in ["a", "i", "we", "to", "is", "it", "on", "my"] {
  check(!AutoSwitchEngine.qualifiesForPhraseExtension(word: word, currentLayout: .english),
        "\(word) is English and must not be swept into a Russian phrase")
}

// MARK: - Whole phrases through the tokenizer

print("=== phrases, typed entirely on the wrong layout")

/// Types a phrase on the wrong layout, tokenizes the result, and applies the
/// engine word by word — including the backward sweep and the layout flip that
/// follows the first correction.
func correctPhrase(_ phrase: String, typedOn wrongLayout: Layout) -> (text: String, fixed: Int, total: Int) {
  let intended = phrase.split(separator: " ").map(String.init)
  let typed = tokenize(intended.map { AutoSwitchEngine.convert($0, to: wrongLayout) }.joined(separator: " "))

  var layout = wrongLayout
  var output: [String] = []
  var pending: [String] = []
  var fixed = 0

  for (index, word) in typed.enumerated() {
    guard layout == wrongLayout else {
      // The layout already flipped, so the rest was typed correctly.
      output.append(intended[index])
      fixed += 1
      continue
    }

    if AutoSwitchEngine.evaluate(word: word, currentLayout: layout) == .switchLayout {
      var sweep: [String] = []
      for earlier in pending.reversed() {
        guard sweep.count < 4,
              AutoSwitchEngine.qualifiesForPhraseExtension(word: earlier, currentLayout: layout) else { break }
        sweep.append(AutoSwitchEngine.convert(earlier, to: layout.other))
      }
      output.removeLast(sweep.count)
      output.append(contentsOf: sweep.reversed())
      output.append(AutoSwitchEngine.convert(word, to: layout.other))
      fixed += sweep.count + 1
      pending = []
      layout = layout.other
    } else {
      pending.append(word)
      output.append(word)
    }
  }
  return (output.joined(separator: " "), fixed, typed.count)
}

let russianPhrases = [
  "я не могу", "у меня нет времени", "и что дальше", "мы с тобой сделаем",
  "он не знает", "это то что нужно", "да я уже сделал", "по поводу встречи",
  "ты где сейчас", "не работает почему то", "можно я скажу", "бизнес план готов",
  "объект не найден", "хорошо давай так",
]
let englishPhrases = [
  "i can not do it", "we have a meeting", "it is a bug", "to be honest",
  "a lot of people", "i am on my way", "do you have a minute", "is it ready yet",
]

var fixedTotal = 0, wordTotal = 0
for phrase in russianPhrases {
  let result = correctPhrase(phrase, typedOn: .english)
  fixedTotal += result.fixed
  wordTotal += result.total
  check(result.fixed == result.total, "\(phrase) -> \(result.text)")
}
print("  Russian on the EN layout: \(fixedTotal)/\(wordTotal)")

var enFixed = 0, enTotal = 0
for phrase in englishPhrases {
  let result = correctPhrase(phrase, typedOn: .russian)
  enFixed += result.fixed
  enTotal += result.total
  check(result.fixed == result.total, "\(phrase) -> \(result.text)")
}
print("  English on the RU layout: \(enFixed)/\(enTotal)")

// MARK: - Full sweep

print("=== full dictionary sweep")
let englishFalsePositives = englishWords.filter {
  AutoSwitchEngine.evaluate(word: $0, currentLayout: .english) == .switchLayout
}
let russianFalsePositives = russianWords.filter {
  AutoSwitchEngine.evaluate(word: $0, currentLayout: .russian) == .switchLayout
}
print("  false positives: EN \(englishFalsePositives.count)/\(englishWords.count), RU \(russianFalsePositives.count)/\(russianWords.count)")
check(englishFalsePositives.isEmpty, "English false positives: \(englishFalsePositives.prefix(10))")
check(russianFalsePositives.isEmpty, "Russian false positives: \(russianFalsePositives.prefix(10))")

var punctuationCorruptions = 0
for word in englishWords where word.count >= 2 {
  for mark in [".", ",", ";"] where AutoSwitchEngine.evaluate(word: word + mark, currentLayout: .english) == .switchLayout {
    punctuationCorruptions += 1
  }
}
print("  English word + trailing punctuation corrupted: \(punctuationCorruptions)")
check(punctuationCorruptions == 0, "trailing punctuation corruptions")

// MARK: - Typo tolerance

print("=== typos: a dropped keystroke still switches the layout")
let typoCases: [(typed: String, meaning: String)] = [
  ("ghdtn",     "привет minus и"),
  ("hf,jftn",   "работает minus т"),
  ("cgfcbj",    "спасибо minus б"),
  ("rjvgm.nth", "компьютер, spelt correctly"),
  ("cjj,otyb",  "сообщение minus е"),
]
for testCase in typoCases {
  check(AutoSwitchEngine.evaluate(word: testCase.typed, currentLayout: .english) == .switchLayout,
        "\(testCase.typed) (\(testCase.meaning)) must switch")
}

print("=== typos: English typed on the Russian layout")
for typed in ["руддщ", "сщьзгеук"] {
  check(AutoSwitchEngine.evaluate(word: typed, currentLayout: .russian) == .switchLayout,
        "\(typed) must switch")
}
// "helo" is "hello" minus an l; typed on the Russian layout that is "руды".
check(AutoSwitchEngine.evaluate(word: "руды", currentLayout: .russian) == .keep,
      "руды is a Russian word and must not be switched")

print("=== typos: too short to judge")
// Under the typo length floor these must not be rescued by a typo match.
// "cgf" is excluded on purpose: it converts to "спа", a real Russian word, so
// it is an exact tier-2 hit rather than a typo.
for typed in ["ghdt", "hfj", "ytr"] {
  check(AutoSwitchEngine.evaluate(word: typed, currentLayout: .english) == .keep,
        "\(typed) is under the typo length floor and must be kept")
}

print("=== typos: an exact match is still distinguishable from a typo match")
check(AutoSwitchEngine.isExactMatch(word: "ghbdtn", currentLayout: .english),
      "ghbdtn is an exact match")
check(!AutoSwitchEngine.isExactMatch(word: "ghdtn", currentLayout: .english),
      "ghdtn is a typo match, not exact")

print("=== typos: measured cost on correctly typed words")
var englishTypoFalsePositives: [String] = []
for word in englishWords where word.count >= LayoutDictionary.minimumTypoLength {
  let converted = AutoSwitchEngine.convert(word, to: .russian)
  guard !LayoutDictionary.shared.contains(converted, in: .russian) else { continue }
  if LayoutDictionary.shared.hasWordOneInsertionAway(converted, in: .russian) {
    englishTypoFalsePositives.append(word)
  }
}
var russianTypoFalsePositives: [String] = []
for word in russianWords where word.count >= LayoutDictionary.minimumTypoLength {
  let converted = AutoSwitchEngine.convert(word, to: .english)
  guard !LayoutDictionary.shared.contains(converted, in: .english) else { continue }
  if LayoutDictionary.shared.hasWordOneInsertionAway(converted, in: .english) {
    russianTypoFalsePositives.append(word)
  }
}
let englishLong = englishWords.filter { $0.count >= LayoutDictionary.minimumTypoLength }.count
let russianLong = russianWords.filter { $0.count >= LayoutDictionary.minimumTypoLength }.count
let englishRate = Double(englishTypoFalsePositives.count) * 100 / Double(englishLong)
let russianRate = Double(russianTypoFalsePositives.count) * 100 / Double(russianLong)
print(String(format: "  EN %d/%d = %.4f%%, RU %d/%d = %.4f%%",
             englishTypoFalsePositives.count, englishLong, englishRate,
             russianTypoFalsePositives.count, russianLong, russianRate))
// Measured at 0.0115% and 0.0170%. Allow headroom for dictionary changes, but
// fail loudly if a change makes typo matching an order of magnitude looser.
check(englishRate < 0.05, "English typo false-positive rate \(englishRate)% exceeds budget")
check(russianRate < 0.05, "Russian typo false-positive rate \(russianRate)% exceeds budget")

// MARK: - Learning from rejected corrections

/// In-memory stand-in for PreferenceStore so the state machine can be driven
/// without touching UserDefaults.
final class FakeMemoryStore: AutoSwitchMemoryStore {
  var rejections: [String: AutoSwitchMemory.Entry] = [:]
  var legacyIgnored: Set<String> = []
  var migrated = false
  var writeCount = 0

  func getAutoSwitchRejections() -> [String: AutoSwitchMemory.Entry] { rejections }
  func setAutoSwitchRejections(_ entries: [String: AutoSwitchMemory.Entry]) {
    rejections = entries
    writeCount += 1
  }
  func getAutoSwitchIgnoredWords() -> Set<String> { legacyIgnored }
  func clearAutoSwitchIgnoredWords() { legacyIgnored = [] }
  func didMigrateAutoSwitchRejections() -> Bool { migrated }
  func setDidMigrateAutoSwitchRejections(_ value: Bool) { migrated = value }
}

let epoch = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

/// Runs one correction and one rejection gesture, settling afterwards.
func reject(_ memory: AutoSwitchMemory, _ word: String, from base: TimeInterval, using gesture: (AutoSwitchMemory, TimeInterval) -> Void) {
  memory.noteCorrection(word: word, at: at(base))
  gesture(memory, base)
  memory.settlePending(now: at(base + 30))
}

func undoGesture(_ memory: AutoSwitchMemory, _ base: TimeInterval) {
  memory.noteActionKey(at: at(base + 1))
}

func revertGesture(_ memory: AutoSwitchMemory, _ base: TimeInterval) {
  memory.noteLayoutReverted(at: at(base + 1))
}

print("=== learning: the threshold fires on exactly the third rejection")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<2 {
    reject(memory, "ghbdtn", from: Double(round) * 100, using: undoGesture)
    check(!memory.shouldSkip(word: "ghbdtn", now: at(500)),
          "must not be skipped after \(round + 1) rejections")
  }
  reject(memory, "ghbdtn", from: 200, using: undoGesture)
  check(memory.shouldSkip(word: "ghbdtn", now: at(500)),
        "must be skipped after 3 rejections")
}

print("=== learning: a layout revert without an edit counts")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<3 {
    reject(memory, "ghbdtn", from: Double(round) * 100, using: revertGesture)
  }
  check(memory.shouldSkip(word: "ghbdtn", now: at(500)),
        "three reverts without edits must reach the threshold")
}

print("=== learning: a layout revert followed by an edit does not count")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<5 {
    let base = Double(round) * 100
    memory.noteCorrection(word: "ghbdtn", at: at(base))
    memory.noteLayoutReverted(at: at(base + 1))
    // The user starts fixing their own text before the suspicion window closes.
    memory.noteTextEdited(at: at(base + 2))
    memory.settlePending(now: at(base + 30))
  }
  check(!memory.shouldSkip(word: "ghbdtn", now: at(600)),
        "editing the text after a revert means the user was fixing their own mistake")
}

print("=== learning: an edit before the revert also cancels it")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<5 {
    let base = Double(round) * 100
    memory.noteCorrection(word: "ghbdtn", at: at(base))
    memory.noteTextEdited(at: at(base + 1))
    memory.noteLayoutReverted(at: at(base + 2))
    memory.settlePending(now: at(base + 30))
  }
  check(!memory.shouldSkip(word: "ghbdtn", now: at(600)),
        "an edit before the revert must block it just as one after does")
}

print("=== learning: one undo is never counted twice")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  // Pressing the action key also changes the layout, so both signals arrive.
  for round in 0..<2 {
    let base = Double(round) * 100
    memory.noteCorrection(word: "ghbdtn", at: at(base))
    memory.noteActionKey(at: at(base + 1))
    memory.noteLayoutReverted(at: at(base + 1))
    memory.settlePending(now: at(base + 30))
  }
  check(!memory.shouldSkip(word: "ghbdtn", now: at(500)),
        "two undos must count as two, not four")
}

print("=== learning: gestures outside the window are ignored")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<5 {
    let base = Double(round) * 1000
    memory.noteCorrection(word: "ghbdtn", at: at(base))
    memory.noteActionKey(at: at(base + AutoSwitchMemory.rejectionWindow + 5))
    memory.settlePending(now: at(base + 100))
  }
  check(!memory.shouldSkip(word: "ghbdtn", now: at(6000)),
        "an action key long after the correction is unrelated to it")
}

print("=== learning: entries expire")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<3 {
    reject(memory, "ghbdtn", from: Double(round) * 100, using: undoGesture)
  }
  check(memory.shouldSkip(word: "ghbdtn", now: at(500)), "blocked initially")
  let afterLifetime = AutoSwitchMemory.entryLifetime + 1000
  check(!memory.shouldSkip(word: "ghbdtn", now: at(afterLifetime)),
        "an entry not reinforced within its lifetime must stop blocking")
}

print("=== learning: migration runs once and preserves old entries")
do {
  let store = FakeMemoryStore()
  store.legacyIgnored = ["it.", "ghbdtn"]
  let memory = AutoSwitchMemory(store: store)
  check(memory.shouldSkip(word: "it."), "migrated word must still be blocked")
  check(memory.shouldSkip(word: "ghbdtn"), "migrated word must still be blocked")
  check(store.migrated, "migration must be marked done")
  check(!store.legacyIgnored.isEmpty,
        "the legacy key must survive so a downgrade does not lose it")

  // A second instance must not migrate again, and must not resurrect words the
  // user has since forgotten.
  store.rejections = [:]
  let second = AutoSwitchMemory(store: store)
  check(!second.shouldSkip(word: "it."), "migration must not run a second time")
}

print("=== learning: forgetting clears everything")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  for round in 0..<3 {
    reject(memory, "ghbdtn", from: Double(round) * 100, using: undoGesture)
  }
  check(memory.learnedWordCount == 1, "one learned word")
  memory.forgetAll()
  check(memory.learnedWordCount == 0, "forgetAll must empty the list")
  check(!memory.shouldSkip(word: "ghbdtn", now: at(500)), "and stop blocking")
  check(store.legacyIgnored.isEmpty, "and clear the legacy list too")
}

print("=== learning: the store is capped")
do {
  let store = FakeMemoryStore()
  let memory = AutoSwitchMemory(store: store)
  // Push well past the cap, each word newer than the last.
  for index in 0..<(AutoSwitchMemory.maximumEntries + 50) {
    reject(memory, "word\(index)", from: Double(index) * 100, using: undoGesture)
  }
  check(store.rejections.count <= AutoSwitchMemory.maximumEntries,
        "stored entries \(store.rejections.count) exceed the cap")
  check(store.rejections["word\(AutoSwitchMemory.maximumEntries + 49)"] != nil,
        "the most recent word must survive eviction")
  check(store.rejections["word0"] == nil,
        "the oldest word must be evicted first")
}

print(failures == 0 ? "\nALL CHECKS PASS" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
