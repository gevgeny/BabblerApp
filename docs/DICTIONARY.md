# Dictionaries

The auto-switch engine decides using two word lists bundled in the app:
`Babbler/Resources/en.txt.gz` (138,804 words) and `ru.txt.gz` (200,121 words),
about 1 MB gzipped and ~12 MB resident once loaded.

## How they are built

`scripts/build_dictionaries.sh` regenerates both. It intersects a spellcheck
word list with an OpenSubtitles frequency list, keeps the top N by frequency,
then merges the curated additions in `dictionaries/`.

| | English | Russian |
| --- | --- | --- |
| Word list | [`dwyl/english-words`](https://github.com/dwyl/english-words) | [`danakt/russian-words`](https://github.com/danakt/russian-words) |
| Frequency | [`hermitdave/FrequencyWords`](https://github.com/hermitdave/FrequencyWords) 2018 en | same, ru |
| Kept | 140,000 | 200,000 |

Why intersect rather than take a raw list? The raw Russian list is 1.5 M forms —
4.5 MB gzipped and far too much resident memory — and has no ordering, so there
is no safe way to trim it. Frequency ranking makes the cut principled. Russian
gets a larger budget because it is heavily inflected: one lemma expands into
dozens of surface forms, all of which people actually type.

## Audit results

Measured against the shipped lists.

### What a gap actually costs

A missing word is **not** a correctness bug. The engine acts only when a word is
absent from the current layout *and* present in the other. So:

- A missing word **typed correctly** is left alone — verified across all 42 gap
  words found in the first audit: **zero** were corrupted.
- A missing word **typed in the wrong layout** simply is not fixed. A missed
  correction, not damage.

This asymmetry is the whole reason the engine is safe to ship.

### Coverage by category

The first audit (before the curated supplements) found core language coverage
was already excellent and the gaps were entirely modern vocabulary:

| Category | Before | After |
| --- | --- | --- |
| RU verbs and inflections | 100% | 100% |
| RU everyday nouns | 90% | 100% |
| RU names and places | 100% | 100% |
| RU slang / internet | 50% | 100% |
| RU business / tech | 33% | 100% |
| RU profanity | 80% | 100% |
| EN UK spellings (colour, organise, centre…) | 100% | 100% |
| EN US spellings (color, organize, center…) | 100% | 100% |
| EN UK-only vocab (lorry, quid, chuffed…) | 95% | 100% |
| EN US-only vocab (truck, bucks, sidewalk…) | 100% | 100% |
| EN slang / internet | 70% | 100% |
| EN profanity | 100% | 100% |
| EN tech | 45% | 100% |

Both UK and US spellings are present in full — the source list is not
regionalised, so `colour`/`color` and `organise`/`organize` all resolve. English
profanity was fully covered from the start; Russian profanity needed only the
softer euphemisms (`задолбал`, `охренеть`) added.

The subtitle-derived frequency lists are the reason tech and internet vocabulary
was weak: film dialogue from before 2018 contains very little `kubernetes` or
`бэклог`. That is exactly what `dictionaries/supplement-*.txt` fixes.

### Accuracy

| Metric | Result |
| --- | --- |
| False positives, 338,925 in-dictionary words | **0** |
| False positives, 231,351 out-of-vocabulary English words | **12 (0.005%)** |
| Recall, Russian typed on EN layout (top 20 k) | **99.7%** |
| Recall, English typed on RU layout (top 20 k) | **99.6%** |

The 12 out-of-vocabulary misfires are obscure three-letter entries (`bde`,
`jnd`, `pfg`). Realistic non-words — `kubernetes`, `nginx`, `qwerty`, `asdf`,
`github`, `recieve`, `teh` — are all left alone.

### Short words and phrase correction

A word of one or two characters is never judged on its own. That is measured,
not cautious:

| Word length | Share of words in one layout that are also a valid word in the other |
| --- | --- |
| 2 | **46%** |
| 3 | **6%** |

But refusing to touch them is not acceptable either — `я не могу` is `z yt vjue`
and fixing only `могу` is barely worth having. So short words are corrected
**with context instead of in isolation**: once a word of three characters or
more switches confidently, that correction sweeps backwards over the words
immediately before it, rewriting any that clearly belong to the other layout.
The sweep stops at the first word that is already valid where it stands, so a
genuinely mixed-language phrase is left alone.

Measured on whole phrases, typing the entire phrase on the wrong layout:

| | Before phrase correction | After |
| --- | --- | --- |
| Russian typed on the EN layout | 80% | **100%** |
| English typed on the RU layout | 90% | **100%** |

### Why the short end of the dictionary is hand-written

Words of one and two letters come exclusively from `dictionaries/short-en.txt`
and `short-ru.txt`. Generated lists contribute nothing below three letters, and
generated three-letter words must rank inside the top 30,000 by frequency.

This is not tidiness. A bogus short entry does real damage:

- `at.` was rewritten as `фею` because the subtitle corpus lists `dc`, `lf`,
  `bk`, `cb` and `ct` as English words, which broke the "is this punctuation or
  a Russian letter?" test.
- `где` stayed broken because `ult` — an obscure abbreviation ranked 214,770 —
  looked like a real English word, which stopped the backward sweep dead and
  left the whole phrase uncorrected.

Both were found in real use, not in theory.

## Extending the dictionaries

Four routes, cheapest first.

### 1. Your own words — no rebuild

Drop a plain text file, one lowercase word per line, `#` for comments:

```
~/Library/Application Support/Babbler/custom-en.txt
~/Library/Application Support/Babbler/custom-ru.txt
```

They are merged into the bundled lists at load time. Restart Babbler to pick up
changes. Best for names, company jargon, project codenames — anything personal
that does not belong in the repo.

### 2. Curated supplements — shipped to everyone

Edit `dictionaries/supplement-en.txt` or `supplement-ru.txt`, then:

```sh
./scripts/build_dictionaries.sh
./scripts/install.sh
```

This is where the tech and internet vocabulary above came from. Use it for
anything a typical user would benefit from.

### 3. Raise the frequency budget

```sh
EN_LIMIT=200000 RU_LIMIT=400000 ./scripts/build_dictionaries.sh
```

Doubling the Russian budget adds ~265 k rarer inflected forms, roughly +900 KB
gzipped and +8 MB resident. Diminishing returns: the tail is rare by definition,
and every added word slightly raises the out-of-vocabulary misfire rate. Re-run
the accuracy audit if you push this far.

### 4. Better sources

- **Hunspell + affix expansion** (`hunspell-ru`, `hunspell-en_GB`,
  `hunspell-en_US`) generates inflections from lemmas and affix rules, giving
  fuller coverage than a fixed form list. Adds a build-time dependency on
  `unmunch`.
- **OpenCorpora** full paradigms for Russian — the most complete open morphology
  available, ~5 M forms. Needs a trie or on-disk index rather than a `Set`.
- **Wiktionary dumps** for both languages, useful for neologisms and slang that
  the 2018 subtitle corpus predates.
- **Regional lists** if UK/US divergence ever matters more than it does today —
  currently both are fully covered, so this is not worth doing.

## Beyond dictionaries

The lookup approach has a hard ceiling: it can never judge a word it has not
seen. The standard next step, and what Punto Switcher actually does, is
**character n-gram scoring**: score a word's letter trigrams against per-language
statistics and pick the more likely language.

That handles names, slang, neologisms and typos with no word list at all, in
about 200 KB of tables instead of 1 MB. The natural design is a hybrid — the
dictionary decides when it knows the word, and n-grams break the tie when it
does not — which would mostly close the remaining out-of-vocabulary gap and
could safely lower the three-character floor to two.

## Memory and load time

Loading happens once, on a background queue, on first use. Until it completes
every lookup returns `false`, so the engine declines to act rather than guess.
Parsing both lists takes roughly 150 ms. Strings of 15 UTF-8 bytes or fewer are
stored inline by Swift, so most entries cost no heap allocation.
