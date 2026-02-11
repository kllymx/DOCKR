#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:-${DOCKR_GITHUB_OWNER:-}}"
REPO="${REPO:-${DOCKR_GITHUB_REPO:-DOCKR}}"
TARGET_APP_PATH="${TARGET_APP_PATH:-/Applications/DOCKR.app}"
OPEN_APP="${OPEN_APP:-1}"
FALLBACK_TO_MAIN="${FALLBACK_TO_MAIN:-0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

detect_owner_from_git_remote() {
  local remote_url path
  remote_url="$(git -C "$SCRIPT_ROOT" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    return
  fi

  case "$remote_url" in
    git@github.com:*)
      path="${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      path="${remote_url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      path="${remote_url#ssh://git@github.com/}"
      ;;
    *)
      return
      ;;
  esac

  path="${path%.git}"
  OWNER="${path%%/*}"
}

for tool in curl unzip mktemp python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool"
    exit 1
  fi
done

if [[ -z "$OWNER" ]]; then
  detect_owner_from_git_remote
fi

if [[ -z "$OWNER" ]]; then
  echo "Missing GitHub owner."
  echo "Run with: OWNER=<github-owner> ./scripts/install-latest-release.sh"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
API_JSON="$WORK_DIR/release.json"
ASSET_PATH="$WORK_DIR/asset"
EXTRACT_DIR="$WORK_DIR/extract"
MOUNT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/latest"
echo "Fetching latest release metadata..."
if ! curl -fsSL "$API_URL" -o "$API_JSON"; then
  if [[ "$FALLBACK_TO_MAIN" == "1" ]]; then
    echo "No published release found yet; falling back to latest main build."
    if [[ -x "$(dirname "$0")/install-latest-main.sh" ]]; then
      exec "$(dirname "$0")/install-latest-main.sh"
    fi
    exec bash <(curl -fsSL "https://raw.githubusercontent.com/${OWNER}/${REPO}/main/scripts/install-latest-main.sh")
  fi
  echo "No published release found for ${OWNER}/${REPO}."
  exit 1
fi

RELEASE_INFO="$(python3 - "$API_JSON" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

tag = data.get('tag_name', '')
name = data.get('name') or tag
assets = data.get('assets', [])
preferred = None
for asset in assets:
    n = asset.get('name', '')
    if n.lower().endswith('.zip') and 'dockr' in n.lower():
        preferred = asset
        break
if preferred is None:
    for asset in assets:
        n = asset.get('name', '')
        if n.lower().endswith('.zip'):
            preferred = asset
            break
if preferred is None:
    for asset in assets:
        n = asset.get('name', '')
        if n.lower().endswith('.dmg'):
            preferred = asset
            break
if preferred is None:
    print(tag)
    print(name)
    print('')
    print('')
    sys.exit(0)
print(tag)
print(name)
print(preferred.get('name', ''))
print(preferred.get('browser_download_url', ''))
PY
)"

TAG="$(printf '%s\n' "$RELEASE_INFO" | sed -n '1p')"
RELEASE_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '2p')"
ASSET_NAME="$(printf '%s\n' "$RELEASE_INFO" | sed -n '3p')"
ASSET_URL="$(printf '%s\n' "$RELEASE_INFO" | sed -n '4p')"

if [[ -z "$ASSET_URL" ]]; then
  echo "No suitable .zip or .dmg asset found in latest release."
  echo "Please publish a release containing a DOCKR app artifact."
  exit 1
fi

echo "Downloading release: ${RELEASE_NAME:-$TAG}"
echo "Asset: $ASSET_NAME"
curl -fL "$ASSET_URL" -o "$ASSET_PATH"

APP_SOURCE_PATH=""

if [[ "$ASSET_NAME" == *.zip ]]; then
  mkdir -p "$EXTRACT_DIR"
  unzip -q "$ASSET_PATH" -d "$EXTRACT_DIR"
  APP_SOURCE_PATH="$(find "$EXTRACT_DIR" -type d -name 'DOCKR.app' | head -n 1)"
elif [[ "$ASSET_NAME" == *.dmg ]]; then
  ATTACH_OUTPUT="$WORK_DIR/attach.txt"
  hdiutil attach -nobrowse -readonly "$ASSET_PATH" | tee "$ATTACH_OUTPUT" >/dev/null
  MOUNT_DIR="$(awk '/\/Volumes\//{for(i=3;i<=NF;i++)printf(i==3?$i:" "$i); printf("\n"); exit}' "$ATTACH_OUTPUT")"
  APP_SOURCE_PATH="$(find "$MOUNT_DIR" -maxdepth 3 -type d -name 'DOCKR.app' | head -n 1)"
else
  echo "Unsupported asset type: $ASSET_NAME"
  exit 1
fi

if [[ -z "$APP_SOURCE_PATH" || ! -d "$APP_SOURCE_PATH" ]]; then
  echo "Could not find DOCKR.app in downloaded asset."
  exit 1
fi

echo "Installing to $TARGET_APP_PATH"
rm -rf "$TARGET_APP_PATH"
cp -R "$APP_SOURCE_PATH" "$TARGET_APP_PATH"
if [[ "$OPEN_APP" == "1" ]]; then
  open "$TARGET_APP_PATH"
fi

echo "Installed DOCKR from release ${TAG}."
