#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/DockLock.app"
TARGET_PATH="/Applications/DockLock.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle missing. Run scripts/build.sh first."
  exit 1
fi

rm -rf "$TARGET_PATH"
cp -R "$APP_PATH" "$TARGET_PATH"
open "$TARGET_PATH"

echo "Installed to $TARGET_PATH"
