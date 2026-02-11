# DOCKR

<p align="center">
  <img src="assets/dockr-logo.png" alt="DOCKR logo" width="140" />
</p>

DOCKR is a lightweight native macOS menu bar app that keeps the Dock anchored to a display you choose.

It is designed for multi-monitor users who want predictable Dock behavior without killing/restarting Dock processes.

## Why DOCKR

macOS can move the Dock between displays based on pointer edge activity. DOCKR prevents that by:

- Watching mouse movement with an Accessibility event tap.
- Blocking Dock-trigger edge events on non-target displays.
- Allowing controlled relock operations from the menu bar when needed.

## Features

- Native AppKit menu bar app (`LSUIElement`) with minimal footprint.
- Per-display target selection with persistence.
- Works with Dock auto-hide on/off.
- Manual `Relock Now` action.
- In-app update checks from menu bar:
  - Stable release updates (recommended).
  - Main-branch updates (advanced, optional).

## macOS Side-Dock Constraint (Important)

This is an Apple platform behavior:

- `left` Dock can only live on displays touching the global far-left edge.
- `right` Dock can only live on displays touching the global far-right edge.
- `bottom` Dock works across more arrangements.

DOCKR marks ineligible displays when Dock is on `left` or `right`.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`clang`) for source builds
- Accessibility permission for DOCKR

## Install Options

### 1. Stable release install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_OWNER>/DOCKR/main/scripts/install-latest-release.sh | bash
```

What it does:
1. Fetches latest GitHub release metadata
2. Downloads release app asset (`.zip` or `.dmg`)
3. Installs `/Applications/DOCKR.app`
4. Launches app

If no release exists yet, it automatically falls back to installing from `main`.

### 2. Main-branch build install (advanced)

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_OWNER>/DOCKR/main/scripts/install-latest-main.sh | bash
```

This rebuilds from source on your machine. Useful for early access/testing.

### 3. Manual local build

```bash
git clone https://github.com/<GITHUB_OWNER>/DOCKR.git
cd DOCKR
scripts/build.sh
scripts/install.sh
```

## First Launch Setup

1. Open `DOCKR`.
2. Grant Accessibility permission when prompted.
3. In menu bar:
   - Enable lock
   - Select target display
   - Use `Relock Now` if Dock is currently off target

Accessibility path:
- System Settings → Privacy & Security → Accessibility

## Updates from Menu Bar

DOCKR intentionally separates update channels:

1. `Check Stable Updates...` (default for normal users)
   - Checks latest GitHub release.
   - If newer semantic version exists, offers update via `install-latest-release.sh`.
2. `Check Development Updates (main)...` (advanced)
   - Checks latest commit on `main`.
   - Offers source-build update via `install-latest-main.sh`.

This keeps everyday UX cleaner and reduces the chance of repeated Accessibility permission churn from frequent source rebuild updates.

## Best UX for Accessibility Permissions (No Apple Developer Account)

To minimize re-authorization prompts across updates:

- Prefer stable release updates over source rebuilds.
- Keep app identity stable:
  - Bundle ID: `io.dockr.app`
  - App path: `/Applications/DOCKR.app`
- Avoid frequent `main` updates for non-technical users.

If permission state becomes stale:

```bash
tccutil reset Accessibility io.dockr.app
```

Then relaunch `/Applications/DOCKR.app` and re-grant.

## Maintainer Guidance (Release Channel)

For the smoothest user updates, publish release artifacts that contain `DOCKR.app` as `.zip` or `.dmg`.

Recommended release process:
1. Build app
2. Sign/notarize with Developer ID
3. Upload `.zip` or `.dmg` to GitHub Release
4. Tag with semantic version (`v0.2.0`, etc.)

The in-app stable updater keys off latest release version tag.

## Scripts

- `scripts/build.sh` - Build local app bundle (`build/DOCKR.app`)
- `scripts/install.sh` - Install local build to `/Applications/DOCKR.app`
- `scripts/install-latest-release.sh` - Install latest GitHub release artifact
- `scripts/install-latest-main.sh` - Install latest source from `main`
- `scripts/generate_icon.sh` - Regenerate `DOCKR.icns`

## App Metadata

- Bundle Identifier: `io.dockr.app`
- Build commit embedded in plist: `BuildGitCommit`
- Update repo settings in plist:
  - `GitHubOwner`
  - `GitHubRepo`
  - `GitDefaultBranch`

## Project Structure

- `DockLock/` - Core app source (Objective-C / AppKit)
- `DockLock/Resources/DOCKR.icns` - App icon
- `scripts/` - Build/install/update helpers

## License

MIT
