#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:-${DOCKR_GITHUB_OWNER:-}}"
REPO="${REPO:-${DOCKR_GITHUB_REPO:-DOCKR}}"
BRANCH="${BRANCH:-main}"
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

for tool in curl unzip mktemp bash; do
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
  echo "Run with: OWNER=<github-owner> ./scripts/install-latest-main.sh"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
ZIP_PATH="$WORK_DIR/${REPO}-${BRANCH}.zip"
EXTRACT_DIR="$WORK_DIR/src"
mkdir -p "$EXTRACT_DIR"

ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${BRANCH}.zip"
echo "Downloading ${ARCHIVE_URL}"
curl -fL "$ARCHIVE_URL" -o "$ZIP_PATH"

unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"
SOURCE_DIR="$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "${REPO}-*" | head -n 1)"

if [[ -z "$SOURCE_DIR" ]]; then
  echo "Could not locate extracted source directory."
  exit 1
fi

cd "$SOURCE_DIR"

if [[ ! -x "scripts/build.sh" || ! -x "scripts/install.sh" ]]; then
  echo "Expected scripts/build.sh and scripts/install.sh in repository."
  exit 1
fi

echo "Building ${REPO} from ${BRANCH}..."
./scripts/build.sh

echo "Installing to /Applications..."
./scripts/install.sh

echo "Update complete."
