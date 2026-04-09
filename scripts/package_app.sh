#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Babbler.xcodeproj}"
SCHEME="${SCHEME:-Babbler}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/package}"
BIN_DIR="${BIN_DIR:-$ROOT_DIR/bin}"
PRODUCT_NAME="${PRODUCT_NAME:-Babbler}"
DEFAULT_XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$ACTIVE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]] && [[ -d "$DEFAULT_XCODE_DEVELOPER_DIR" ]]; then
        export DEVELOPER_DIR="$DEFAULT_XCODE_DEVELOPER_DIR"
    fi
fi

if ! xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild is unavailable. Install Xcode or set DEVELOPER_DIR to a full Xcode developer directory." >&2
    exit 1
fi

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Built app not found at $APP_PATH" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_PATH")"
ZIP_PATH="$BIN_DIR/$PRODUCT_NAME v$VERSION.zip"

mkdir -p "$BIN_DIR"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created $ZIP_PATH"
