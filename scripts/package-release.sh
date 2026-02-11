#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/DOCKR.app"
DIST_DIR="$ROOT_DIR/dist"
PLIST_PATH="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing build/DOCKR.app. Run scripts/build.sh first."
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="unknown"
fi

mkdir -p "$DIST_DIR"
ARCHIVE_PATH="$DIST_DIR/DOCKR-v${VERSION}-macos.zip"
rm -f "$ARCHIVE_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

echo "Packaged: $ARCHIVE_PATH"
