#!/bin/zsh
#
# Rebuilds Babbler/Resources/{en,ru}.txt.gz from public word lists.
#
# The bundled dictionaries are the intersection of a spellcheck word list with
# an OpenSubtitles frequency list, cut to a size that keeps the app's memory
# footprint reasonable, plus the curated files in dictionaries/.
#
# Run this after editing anything in dictionaries/, then rebuild the app.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Babbler/Resources"
SUPP_DIR="$ROOT_DIR/dictionaries"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Word forms kept per language. Russian needs far more because it is heavily
# inflected: one lemma expands to dozens of surface forms.
EN_LIMIT="${EN_LIMIT:-140000}"
RU_LIMIT="${RU_LIMIT:-200000}"
# Frequency-rank cutoff for generated three-letter words (see the note in the
# Python block). Curated words in dictionaries/ are never subject to it.
SHORT_RANK_LIMIT="${SHORT_RANK_LIMIT:-30000}"

EN_WORDS_URL="https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt"
RU_WORDS_URL="https://raw.githubusercontent.com/danakt/russian-words/master/russian.txt"
EN_FREQ_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_full.txt"
RU_FREQ_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_full.txt"

echo "==> Downloading source lists..."
curl -sSL --max-time 300 -o "$WORK_DIR/en_words.txt" "$EN_WORDS_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/ru_words.raw" "$RU_WORDS_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/en_freq.txt"  "$EN_FREQ_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/ru_freq.txt"  "$RU_FREQ_URL"

# Everything below is done in Python on purpose. This pipeline is all about
# character counts and case folding on Cyrillic, and the BSD shell tools get
# both wrong: `awk`'s length() counts bytes, so every two-letter Cyrillic word
# measures 4 and slips past a "3 or more" filter, and `tr 'А-ЯЁ' 'а-яё'` expands
# its ranges bytewise and mangles multi-byte input. Both failures are silent.
echo "==> Building dictionaries..."
python3 - "$WORK_DIR" "$SUPP_DIR" "$OUT_DIR" "$EN_LIMIT" "$RU_LIMIT" "$SHORT_RANK_LIMIT" <<'PY'
import gzip, re, sys
from pathlib import Path

work, supp, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
EN_LIMIT = int(sys.argv[4])
RU_LIMIT = int(sys.argv[5])
limits = {"en": EN_LIMIT, "ru": RU_LIMIT}
# Three-letter words are the last high-collision zone: short enough that a
# layout flip lands on another real word, long enough to clear the length floor.
# The tail of the frequency list is full of junk at that length ("ult" ranks
# 214770, "abb", "abt", "aby"), and one such entry blocks a whole phrase - "где"
# stayed broken because "ult" looked like a word. Generated three-letter words
# therefore have to be reasonably common; curated ones bypass this.
SHORT_RANK_LIMIT = int(sys.argv[6])
out.mkdir(parents=True, exist_ok=True)

WORD_RE = {"en": re.compile(r"^[a-z]+$"), "ru": re.compile(r"^[а-яё]+$")}


def read_lines(path, encoding="utf-8"):
    with open(path, encoding=encoding, errors="replace") as handle:
        for line in handle:
            yield line.strip()


def valid_words(path, lang, encoding="utf-8"):
    """Spellcheck-valid forms: lowercase, alphabetic, at least two characters."""
    pattern = WORD_RE[lang]
    return {w for w in (l.lower() for l in read_lines(path, encoding))
            if len(w) >= 2 and pattern.match(w)}


def ranked(freq_path, valid, lang, limit):
    """Valid forms ordered by corpus frequency, capped at `limit`.

    Only words of three characters or more: one- and two-letter entries come
    from the hand-checked whitelist instead. The frequency lists are full of
    short subtitle noise ("dc", "lf", "цу", "ше"), and a bogus short word is
    unusually harmful - it decides whether "at." is punctuation or the Russian
    "фею", and short words are what retroactive phrase correction walks back
    over.
    """
    pattern, seen, kept = WORD_RE[lang], set(), []
    for index, line in enumerate(read_lines(freq_path)):
        word = line.split(" ")[0].lower()
        if len(word) < 3 or word in seen or word not in valid:
            continue
        if not pattern.match(word):
            continue
        if len(word) == 3 and index >= SHORT_RANK_LIMIT:
            continue
        seen.add(word)
        kept.append(word)
        if len(kept) >= limit:
            break
    return kept


def curated(path, lang, min_len, max_len):
    if not path.exists():
        return set()
    pattern = WORD_RE[lang]
    words = set()
    for line in read_lines(path):
        word = line.split("#")[0].strip().lower()
        if word and min_len <= len(word) <= max_len and pattern.match(word):
            words.add(word)
    return words


sources = {
    "en": (work / "en_words.txt", work / "en_freq.txt", "utf-8"),
    "ru": (work / "ru_words.raw", work / "ru_freq.txt", "cp1251"),
}

for lang, (words_path, freq_path, encoding) in sources.items():
    valid = valid_words(words_path, lang, encoding)
    final = set(ranked(freq_path, valid, lang, limits[lang]))
    final |= curated(supp / f"supplement-{lang}.txt", lang, 3, 64)
    final |= curated(supp / f"short-{lang}.txt", lang, 1, 2)

    target = out / f"{lang}.txt.gz"
    payload = ("\n".join(sorted(final)) + "\n").encode("utf-8")
    with gzip.GzipFile(target, "wb", compresslevel=9, mtime=0) as handle:
        handle.write(payload)

    short = sum(1 for w in final if len(w) <= 2)
    print(f"    {lang}: {len(final)} words ({short} of 1-2 letters), "
          f"{target.stat().st_size // 1024} KB")
PY

echo "==> Done. Rebuild the app to pick them up: ./scripts/install.sh"
