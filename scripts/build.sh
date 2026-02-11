#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DOCKR"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BUNDLE_ID="${DOCKR_BUNDLE_ID:-io.dockr.app}"
GITHUB_OWNER="${DOCKR_GITHUB_OWNER:-}"
GITHUB_REPO="${DOCKR_GITHUB_REPO:-DOCKR}"
GIT_DEFAULT_BRANCH="${DOCKR_GIT_DEFAULT_BRANCH:-main}"

set_plist_key() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    /usr/libexec/PlistBuddy -c "Set :${key} \"\"" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || \
      /usr/libexec/PlistBuddy -c "Add :${key} string \"\"" "$APP_DIR/Contents/Info.plist"
    return
  fi

  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "$APP_DIR/Contents/Info.plist"
}

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

set_plist_key "CFBundleIdentifier" "$BUNDLE_ID"
set_plist_key "GitHubOwner" "$GITHUB_OWNER"
set_plist_key "GitHubRepo" "$GITHUB_REPO"
set_plist_key "GitDefaultBranch" "$GIT_DEFAULT_BRANCH"

BUILD_GIT_COMMIT="unknown"
if git -C "$ROOT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
  BUILD_GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
fi
set_plist_key "BuildGitCommit" "$BUILD_GIT_COMMIT"

# Bundle-sign so macOS tracks a stable app identity for Accessibility permissions.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_DIR"

echo "Built: $APP_DIR"
