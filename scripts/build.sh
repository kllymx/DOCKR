#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DockLock"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$BIN_DIR" "$RES_DIR"

clang -fobjc-arc -fmodules \
  -framework Cocoa \
  -framework CoreGraphics \
  -framework ApplicationServices \
  "$ROOT_DIR/DockLock/main.m" \
  "$ROOT_DIR/DockLock/AppDelegate.m" \
  "$ROOT_DIR/DockLock/DockLockController.m" \
  "$ROOT_DIR/DockLock/GitHubUpdater.m" \
  -o "$BIN_DIR/$APP_NAME"

cp "$ROOT_DIR/DockLock/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built: $APP_DIR"
