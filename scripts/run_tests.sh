#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
mkdir -p "$BUILD_DIR/module-cache"

xcrun swiftc -module-cache-path "$BUILD_DIR/module-cache" \
  "$ROOT_DIR/Babbler/Key.swift" "$ROOT_DIR/Babbler/PreferenceStore.swift" \
  "$ROOT_DIR/tests/PreferenceStoreTests.swift" -o "$BUILD_DIR/preferences"
"$BUILD_DIR/preferences"

KEYBOARD_SOURCES=(
  "$ROOT_DIR/Babbler/Key.swift"
  "$ROOT_DIR/Babbler/PreferenceStore.swift"
  "$ROOT_DIR/Babbler/KeyboardUtils.swift"
  "$ROOT_DIR/Babbler/InputSourceUtils.swift"
  "$ROOT_DIR/Babbler/TISInputSourceExtension.swift"
  "$ROOT_DIR/Babbler/KeyDictionary.swift"
)
for TEST_NAME in KeyboardUtilsTests ActionKeyTests; do
  xcrun swiftc -module-cache-path "$BUILD_DIR/module-cache" \
    "${KEYBOARD_SOURCES[@]}" "$ROOT_DIR/tests/$TEST_NAME.swift" -o "$BUILD_DIR/$TEST_NAME"
  "$BUILD_DIR/$TEST_NAME"
done
