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

print(failures == 0 ? "\nALL CHECKS PASS" : "\n\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
