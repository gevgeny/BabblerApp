#!/bin/zsh
#
# Regression suite for the auto-switch tokenizer and engine.
#
# Not an XCTest target: the app has no test target, and these checks need the
# real gzipped dictionaries from Babbler/Resources. Compiling the three source
# files directly keeps it dependency-free and runnable from any shell.
#
#   ./tests/run.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# LayoutDictionary keeps gunzip and its storage private. Expose both for the
# harness rather than weakening the shipping API.
sed -e 's/private static func gunzip/static func testGunzipImpl/' \
    -e 's/gunzip(compressed)/testGunzipImpl(compressed)/' \
    "$ROOT_DIR/Babbler/LayoutDictionary.swift" > "$WORK_DIR/LayoutDictionary.swift"

python3 - "$WORK_DIR/LayoutDictionary.swift" <<'PY'
import sys
path = sys.argv[1]
source = open(path).read()
hook = """  func setForTests(_ en: Set<String>, _ ru: Set<String>) {
    lock.lock(); english = en; russian = ru; isLoaded = true; lock.unlock()
  }
  static func testGunzip(_ data: Data) -> String? { testGunzipImpl(data) }

  func contains("""
open(path, "w").write(source.replace("  func contains(", hook, 1))
PY

cp "$ROOT_DIR/Babbler/AutoSwitchEngine.swift" "$ROOT_DIR/Babbler/KeyDictionary.swift" "$WORK_DIR/"
cp "$ROOT_DIR/tests/AutoSwitchTests.swift" "$WORK_DIR/main.swift"

swiftc -O -o "$WORK_DIR/tests" \
    "$WORK_DIR/main.swift" \
    "$WORK_DIR/LayoutDictionary.swift" \
    "$WORK_DIR/AutoSwitchEngine.swift" \
    "$WORK_DIR/KeyDictionary.swift"

BABBLER_RESOURCES="$ROOT_DIR/Babbler/Resources" "$WORK_DIR/tests"
