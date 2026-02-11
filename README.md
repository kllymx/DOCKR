# DOCKR

DOCKR is a lightweight native macOS menu bar app that keeps the Dock anchored to the display you choose.

It is built for multi-monitor setups where macOS normally moves the Dock based on pointer edge activity.

## What DOCKR Does

- Anchors Dock behavior to a selected display.
- Runs as a minimal menu bar utility (`LSUIElement`).
- Prevents Dock edge-trigger moves on non-target displays (Accessibility event tap).
- Supports manual relock on demand.
- Checks for updates from GitHub `main` directly in the menu bar.

## Important macOS Behavior

macOS has a hard platform rule for side-oriented Dock:

- `left` Dock: only displays on the global far-left desktop edge can host the Dock.
- `right` Dock: only displays on the global far-right desktop edge can host the Dock.
- `bottom` Dock: generally works across more layouts.

DOCKR marks unsupported displays in the menu when Dock is set to `left` or `right`.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`clang`)
- Accessibility permission for DOCKR

## Install

### Option 1: One-command install from `main` (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/DOCKR/main/scripts/install-latest-main.sh | bash
```

This will:
1. Download latest source from `main`
2. Build the app
3. Install to `/Applications/DOCKR.app`
4. Launch it

### Option 2: Build locally

```bash
git clone https://github.com/<user>/DOCKR.git
cd DOCKR
scripts/build.sh
scripts/install.sh
```

## Usage

1. Open `DOCKR` from Applications.
2. Grant Accessibility access when prompted.
3. Use menu bar icon to:
   - Enable/disable lock
   - Select target display
   - Relock now

## Updates from Menu Bar

DOCKR checks GitHub commits on `main`.

- Menu item: `Check for Updates...`
- If a newer commit is found, DOCKR can run update installer in Terminal automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/DOCKR/main/scripts/install-latest-main.sh | bash
```

This means users can update directly from the menu bar when new code is pushed to `main`.

## Accessibility Permission

DOCKR requires Accessibility permission to monitor/block edge-trigger mouse movement events.

Path:
- System Settings → Privacy & Security → Accessibility

If permission seems stale after reinstall:

```bash
tccutil reset Accessibility io.dockr.app
```

Then relaunch `/Applications/DOCKR.app` and re-grant permission.

## Build Outputs

- App bundle: `build/DOCKR.app`
- Installed app: `/Applications/DOCKR.app`

Build script automatically embeds current git commit SHA into `Info.plist` (`BuildGitCommit`) for update comparison.

## Icon

DOCKR includes a generated custom lock icon (`DOCKR.icns`).

To regenerate:

```bash
scripts/generate_icon.sh
```

## Project Layout

- `DockLock/` - App source (Objective-C / AppKit)
- `scripts/build.sh` - Local build
- `scripts/install.sh` - Local install to Applications
- `scripts/install-latest-main.sh` - Remote install/update script
- `scripts/generate_icon.sh` - Icon generation

## Distribution Model

DOCKR is intended for open-source GitHub distribution (not App Store sandbox constraints).

## License

MIT
