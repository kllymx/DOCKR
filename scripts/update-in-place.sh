#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:-${DOCKR_GITHUB_OWNER:-}}"
REPO="${REPO:-${DOCKR_GITHUB_REPO:-DOCKR}}"
TARGET_APP_PATH="${TARGET_APP_PATH:-/Applications/DOCKR.app}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-io.dockr.app}"
APP_PID="${APP_PID:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$OWNER" ]]; then
  echo "Missing GitHub owner. Set OWNER=<github-owner>."
  exit 1
fi

quit_running_app() {
  if [[ -n "$APP_BUNDLE_ID" ]]; then
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  fi

  if [[ -n "$APP_PID" ]]; then
    kill -TERM "$APP_PID" >/dev/null 2>&1 || true
  fi

  sleep 1
}

install_latest_release() {
  if [[ -x "$SCRIPT_DIR/install-latest-release.sh" ]]; then
    OWNER="$OWNER" REPO="$REPO" TARGET_APP_PATH="$TARGET_APP_PATH" OPEN_APP=0 FALLBACK_TO_MAIN=0 "$SCRIPT_DIR/install-latest-release.sh"
    return
  fi

  OWNER="$OWNER" REPO="$REPO" TARGET_APP_PATH="$TARGET_APP_PATH" OPEN_APP=0 FALLBACK_TO_MAIN=0 \
    bash <(curl -fsSL "https://raw.githubusercontent.com/${OWNER}/${REPO}/main/scripts/install-latest-release.sh")
}

quit_running_app
install_latest_release
open "$TARGET_APP_PATH"

echo "DOCKR updated and relaunched."
