#!/bin/zsh
#
# Rebuilds Babbler/Resources/{en,ru}.txt.gz from public word lists.
#
# The bundled dictionaries are the intersection of a spellcheck word list with
# an OpenSubtitles frequency list, cut to a size that keeps the app's memory
# footprint reasonable, plus the curated additions in dictionaries/.
#
# Run this after editing dictionaries/supplement-*.txt, then rebuild the app.

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

EN_WORDS_URL="https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt"
RU_WORDS_URL="https://raw.githubusercontent.com/danakt/russian-words/master/russian.txt"
EN_FREQ_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_full.txt"
RU_FREQ_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_full.txt"

echo "==> Downloading source lists..."
curl -sSL --max-time 300 -o "$WORK_DIR/en_words.txt" "$EN_WORDS_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/ru_words.raw" "$RU_WORDS_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/en_freq.txt"  "$EN_FREQ_URL"
curl -sSL --max-time 300 -o "$WORK_DIR/ru_freq.txt"  "$RU_FREQ_URL"

echo "==> Normalising..."
# The Russian source is Windows-1251.
iconv -f WINDOWS-1251 -t UTF-8 "$WORK_DIR/ru_words.raw" \
  | tr -d '\r' | tr 'А-ЯЁ' 'а-яё' | grep -E '^[а-яё]{2,}$' | sort -u > "$WORK_DIR/ru_valid.txt"
tr -d '\r' < "$WORK_DIR/en_words.txt" \
  | tr 'A-Z' 'a-z' | grep -E '^[a-z]{2,}$' | sort -u > "$WORK_DIR/en_valid.txt"

echo "==> Ranking by frequency..."
# Keep only words that are both spellcheck-valid and observed in real text,
# in descending frequency order, then take the top N.
rank() {  # $1 = freq list, $2 = valid list, $3 = limit, $4 = output
    # Filter without exiting early: `head`, or an awk `exit`, closes the pipe and
    # kills the upstream process with SIGPIPE, which pipefail turns into a
    # build failure. Reading the whole list costs a couple of seconds.
    awk '{print $1}' "$1" | tr 'A-ZА-ЯЁ' 'a-zа-яё' \
      | awk -v valid="$2" -v limit="$3" \
            'BEGIN{while((getline l < valid)>0) v[l]}
             ($0 in v) && !seen[$0]++ && n < limit { print; n++ }' \
      > "$4"
}
rank "$WORK_DIR/en_freq.txt" "$WORK_DIR/en_valid.txt" "$EN_LIMIT" "$WORK_DIR/en_ranked.txt"
rank "$WORK_DIR/ru_freq.txt" "$WORK_DIR/ru_valid.txt" "$RU_LIMIT" "$WORK_DIR/ru_ranked.txt"

echo "==> Merging curated supplements..."
strip_comments() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null | tr -d '\r' | tr 'A-ZА-ЯЁ' 'a-zа-яё' || true; }
cat "$WORK_DIR/en_ranked.txt" <(strip_comments "$SUPP_DIR/supplement-en.txt") | sort -u > "$WORK_DIR/en_final.txt"
cat "$WORK_DIR/ru_ranked.txt" <(strip_comments "$SUPP_DIR/supplement-ru.txt") | sort -u > "$WORK_DIR/ru_final.txt"

mkdir -p "$OUT_DIR"
gzip -9 -c "$WORK_DIR/en_final.txt" > "$OUT_DIR/en.txt.gz"
gzip -9 -c "$WORK_DIR/ru_final.txt" > "$OUT_DIR/ru.txt.gz"

echo "==> Done."
printf "    en: %s words, %s\n" "$(wc -l < "$WORK_DIR/en_final.txt" | tr -d ' ')" "$(du -h "$OUT_DIR/en.txt.gz" | cut -f1)"
printf "    ru: %s words, %s\n" "$(wc -l < "$WORK_DIR/ru_final.txt" | tr -d ' ')" "$(du -h "$OUT_DIR/ru.txt.gz" | cut -f1)"
echo "    Rebuild the app to pick them up: ./scripts/install.sh"
