// MARK: - Russian (ЙЦУКЕН standard Apple layout)

let latinToRussianDict: [String: String] = [
    "§": "ё",
    "1": "1", "2": "2", "3": "3", "4": "4", "5": "5",
    "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",
    "-": "-", "=": "=",
    "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
    "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
    "[": "х", "]": "ъ",
    "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
    "h": "р", "j": "о", "k": "л", "l": "д",
    ";": "ж", "'": "э", "\\": "\\", "`": "]",
    "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
    "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
    "±": "Ё", "!": "!", "@": "\"", "#": "№", "$": ";",
    "%": "%", "^": ":", "&": "?", "*": "*",
    "(": "(", ")": ")", "_": "_", "+": "+",
    "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
    "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
    "{": "Х", "}": "Ъ",
    "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
    "H": "Р", "J": "О", "K": "Л", "L": "Д",
    ":": "Ж", "\"": "Э", "|": "/", "~": "[",
    "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
    "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ","
]

// MARK: - Ukrainian (ЙЦУКЕН)
// Same physical layout as Russian except four key positions:
//   s/S  → і/І  (Ukrainian і, replaces Russian ы)
//   ]/}  → ї/Ї  (Ukrainian ї, replaces Russian ъ)
//   '/\" → є/Є  (Ukrainian є, replaces Russian э)
//   §/±  → ґ/Ґ  (Ukrainian ґ, replaces Russian ё)

let latinToUkrainianDict: [String: String] = {
    var d = latinToRussianDict
    d["s"] = "і";  d["S"] = "І"
    d["]"] = "ї";  d["}"] = "Ї"
    d["'"] = "є";  d["\""] = "Є"
    d["§"] = "ґ";  d["±"] = "Ґ"
    return d
}()

// MARK: - Layout lookup tables

private let latinToCyrillicByLayout: [String: [String: String]] = [
    "com.apple.keylayout.Russian":      latinToRussianDict,
    "com.apple.keylayout.RussianWin":   latinToRussianDict,
    "com.apple.keylayout.Ukrainian":    latinToUkrainianDict,
    "com.apple.keylayout.Ukrainian-PC": latinToUkrainianDict,
]

private let cyrillicToLatinByLayout: [String: [String: String]] = {
    var result: [String: [String: String]] = [:]
    for (layoutId, dict) in latinToCyrillicByLayout {
        result[layoutId] = Dictionary(dict.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }
    return result
}()

// MARK: - Public accessors
// Falls back to Russian when the layout is not explicitly mapped.

func latinToCyrillicDict(for layoutId: String) -> [String: String] {
    latinToCyrillicByLayout[layoutId]
        ?? latinToCyrillicByLayout["com.apple.keylayout.Russian"]!
}

func cyrillicToLatinDict(for layoutId: String) -> [String: String] {
    cyrillicToLatinByLayout[layoutId]
        ?? cyrillicToLatinByLayout["com.apple.keylayout.Russian"]!
}
