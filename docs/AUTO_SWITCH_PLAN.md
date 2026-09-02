# Auto layout switch — MVP design plan

Goal: when a word is typed in the wrong keyboard layout, Babbler detects it on
the word boundary and rewrites it in the correct layout automatically, the way
Punto Switcher and Caramba Switcher do. Today the same correction exists but is
manual — the user presses the action key.

Estimate: ~2 days for the MVP below, ~4 days including the polish items.

## 1. What already exists

Almost all the machinery is in place; the feature is mostly a decision layer on
top of it.

| Need | Existing code |
| --- | --- |
| Character mapping EN↔RU | `KeyDictionary.enRuDictionary` / `ruEnDictionary` |
| Convert a string between layouts | `KeyboardUtils.translateText` |
| Replay a recorded word in the other layout | `KeyboardUtils.replaceTypedText` |
| Buffer of the word being typed | `AppDelegate.wordRecord` + `text` |
| Word-boundary detection | `AppDelegate.handleGlobalSystemEvent` (space/enter/punctuation reset `wordRecord`) |
| Change the system input source | `InputSourceUtils.swapLang` |
| Guard against re-recording synthetic keys | `isWaitingForSwitch` + watchdogs |

Missing: the dictionaries and the decision rule.

## 2. Architecture

```
keyDown ──► AppDelegate.handleGlobalSystemEvent
                │  (existing) append to wordRecord / text
                │
                └─ on word boundary ──► AutoSwitchEngine.evaluate(text)
                                              │
                                              ├─ .keep          → do nothing
                                              └─ .switchLayout  → beginSwitch(wordRecord)
                                                                  (existing path)
```

Two new files:

- `Babbler/AutoSwitch/Dictionary.swift` — loads and queries the word lists.
- `Babbler/AutoSwitch/AutoSwitchEngine.swift` — the decision rule.

`AppDelegate` gains one call at the existing word-boundary branch. No change to
the replacement path — it reuses `beginSwitch`, so the correction behaves
exactly like a manual action-key press, including the watchdogs.

## 3. Dictionaries

**Sources**

- English: `dwyl/english-words` (`words_alpha.txt`, ~370k, public domain).
  Trim to the ~100k most common to keep the bundle small.
- Russian: OpenCorpora or `hunspell-ru` lemma list, ~150k forms.

**Format** — plain UTF-8, one lowercase word per line, sorted, gzipped in the
app bundle (`en.txt.gz`, `ru.txt.gz`, ~1.5 MB total compressed).

**Loading** — lazily on first use, off the main thread, into two
`Set<String>` for O(1) lookup. ~10–15 MB resident, ~150 ms to parse. Acceptable
for a menu-bar app; a `.plist`-backed trie is a later optimisation, not MVP.

```swift
final class LayoutDictionary {
  private var en: Set<String> = []
  private var ru: Set<String> = []
  private var loaded = false

  func contains(_ word: String, in lang: Lang) -> Bool
  func preload()   // called from finishApplicationSetup on a background queue
}
```

## 4. Decision rule

On word boundary, with `word` = the text just typed and `current` = the active
input source:

```
1. Reject early (return .keep) if:
     - word.count < 3                     // "ok", "hi", "и"
     - word contains a digit               // "abc123", version numbers
     - word contains @ / : / / / \ / _ / . // emails, URLs, paths, code
     - word is not entirely lowercase      // proper nouns, ACRONYMS
     - the app is in the user's exclusion list

2. asIs      = dictionary.contains(word, in: current)
   converted = translateText(word, to: other(current))
   asOther   = dictionary.contains(converted, in: other(current))

3. if  asOther && !asIs  → .switchLayout
   else                  → .keep
```

The rule is deliberately conservative: it only fires when the typed word is
**not** a word in the current layout **and is** a word in the other one. A
false positive is far more annoying than a missed correction.

`translateText` already handles the character mapping; the engine only needs to
lowercase and strip trailing punctuation before lookup.

## 5. Undo

Punto's most important affordance. After an automatic switch:

- Pressing the action key within ~5 s reverts the word and re-swaps the layout
  back. `wordRecord` is already preserved across a swap, so this is a second
  `beginSwitch(wordRecord)` — it works today with no extra code.
- Pressing Backspace immediately after also reverts, then continues normally.
- Track `lastAutoSwitch: (record, date)?` in `AppDelegate` to scope both.

Additionally: if the user manually undoes the same word twice, add it to a
per-user ignore list in `UserDefaults` so it is never auto-switched again.

## 6. Settings

Add to `SettingsView` under a new "Auto switch" section:

- `Toggle` — "Switch layout automatically" (`autoSwitchEnabledKey`, default
  **off** for the MVP so existing behaviour is unchanged on upgrade).
- `Toggle` — "Play a sound on auto switch".
- A list of excluded apps, reusing the existing app-picker component from the
  per-app input source mapping.

New keys in `PreferenceStore.swift` alongside the existing ones.

## 7. Edge cases to handle

| Case | Handling |
| --- | --- |
| Passwords | Skip while `SecurityInputUtils` reports secure input |
| Terminal / IDE | Ship a default exclusion list (Terminal, iTerm, Xcode, VS Code) |
| URLs, emails, paths | Rejected by the punctuation rule |
| Short words | `count < 3` rejected |
| Proper nouns | Non-lowercase rejected |
| Words valid in both layouts | `asIs` true → `.keep` |
| Mixed-language sentences | Per-word decision, so this works naturally |
| Fast typing | Decision runs on the main thread but is two set lookups — negligible |

## 8. Phases

**Phase 1 — dictionaries (0.5 d)**
Source, trim, gzip, add to the bundle. Implement `LayoutDictionary` with lazy
background loading. Unit-test lookup and memory.

**Phase 2 — engine (0.5 d)**
`AutoSwitchEngine.evaluate`. Pure function, no side effects — unit-test with a
table of ~50 real-world cases (`ghbdtn` → switch, `hello` → keep,
`привет` → keep, `ok` → keep, `user@host.com` → keep).

**Phase 3 — wiring (0.5 d)**
Call the engine from the word-boundary branch in `handleGlobalSystemEvent`;
route a positive result into `beginSwitch`. Add `lastAutoSwitch` and the undo
window.

**Phase 4 — settings + polish (0.5 d)**
Preference keys, `SettingsView` section, default exclusion list, optional
sound, ignore-list persistence.

## 9. Out of scope for the MVP

- Whole-sentence / retroactive correction of already-typed text.
- Learning from user corrections beyond the simple ignore list.
- Layouts other than EN and RU.
- Trie/`mmap`-backed dictionary to cut memory below 5 MB.

---

## Implementation notes (shipped)

The MVP is implemented. Deviations from the plan above, and why:

**Dictionaries.** English is `dwyl/english-words` intersected with the
OpenSubtitles 2018 frequency list (`hermitdave/FrequencyWords`), giving 138,727
forms. Russian is `danakt/russian-words` intersected with the same frequency
list and cut to the 200,000 most frequent forms. Intersecting with a frequency
list was necessary: the raw Russian list is 1.5 M forms (4.5 MB gzipped, far too
much resident memory) and has no ordering, so it could not be trimmed safely.
Shipped as `Babbler/Resources/{en,ru}.txt.gz`, 980 KB total.

**Gzip.** Foundation has no public gzip API, so `LayoutDictionary` skips the
gzip header by hand and inflates the payload with `libcompression`
(`COMPRESSION_ZLIB`).

**Punctuation rule — the important correction.** The plan proposed rejecting any
word containing punctuation. That is wrong: `б ю ж э х ъ` sit on the `, . ; ' [ ]`
keys, so a Russian word typed on the English layout is *full* of punctuation —
`компьютер` is typed as `rjvgm.nth`. Rejecting those would have blinded the
engine to its single most common case. Instead the disqualifying set excludes
those characters, and eligibility of the *converted* candidate is enforced by
requiring it to be all letters.

**Word boundary.** Evaluation runs on the keystroke that ends the word (space,
enter, or `.,!?;:`). Because the monitor is passive, that terminator has already
reached the focused app, so it is appended to the record and replayed with the
word. Its keycode is layout independent, so this is safe.

**Undo.** After a correction the corrected run is left in `wordRecord`, so
pressing the action key immediately swaps it straight back — no new code path.
Two undos of the same word add it to a persistent ignore list.

**Measured quality** (full-dictionary sweep, see commit message):

| Metric | Result |
| --- | --- |
| False positives on 338,727 in-dictionary words | 0 |
| False positives on 231,351 out-of-vocabulary words | 12 (0.005%) |
| Recall, Russian typed on EN layout (top 20 k) | 99.7% |
| Recall, English typed on RU layout (top 20 k) | 99.6% |

Realistic non-words — `kubernetes`, `nginx`, `qwerty`, `asdf`, `github`,
`recieve`, `teh` — are all correctly left alone.

**Not implemented** (deliberately deferred, as in "Out of scope"): the sound
option and the excluded-apps editor UI. The exclusion list itself works and
ships with a sensible default (Terminal, iTerm, Warp, Xcode, VS Code, IntelliJ,
1Password); it is editable via `defaults write eugene.Babbler autoSwitchExcludedApps`.
