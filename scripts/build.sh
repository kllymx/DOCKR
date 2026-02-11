#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DOCKR"
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
if [[ -d "$ROOT_DIR/DockLock/Resources" ]]; then
  cp -R "$ROOT_DIR/DockLock/Resources/." "$RES_DIR/"
fi

BUILD_GIT_COMMIT="unknown"
if git -C "$ROOT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
  BUILD_GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
fi
/usr/libexec/PlistBuddy -c "Set :BuildGitCommit $BUILD_GIT_COMMIT" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Add :BuildGitCommit string $BUILD_GIT_COMMIT" "$APP_DIR/Contents/Info.plist"

# Bundle-sign so macOS tracks a stable app identity for Accessibility permissions.
codesign --force --deep --sign - --identifier io.dockr.app "$APP_DIR"

echo "Built: $APP_DIR"
