# DockLock

DockLock is a lightweight macOS menu bar utility that keeps the Apple Dock pinned to a selected display.

## How It Works

macOS does not expose a public API to set the Dock display directly. DockLock uses an Accessibility event tap to block Dock-trigger mouse movement on non-target displays, plus a one-shot relock routine when needed.

Design goals:
- Works whether Dock auto-hide is enabled or disabled.
- Lets you pick a specific display (external or built-in).
- Keeps running quietly from the menu bar.
- Supports GitHub release update checks from the menu.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`clang`)
- Accessibility permission for DockLock (System Settings > Privacy & Security > Accessibility)

## Build

```bash
scripts/build.sh
```

This produces:
- `build/DockLock.app`

## Install

```bash
scripts/install.sh
```

This copies the app to `/Applications/DockLock.app` and launches it.

## Usage

1. Click the DockLock menu bar icon.
2. Choose `Lock Target` display.
3. Keep `Enable Lock` on.
4. Use `Relock Now` anytime.

On first enable, macOS will prompt for Accessibility access. Without this permission, lock protection cannot work.

## Updating from the Menu Bar

`Check for Updates...` queries `https://api.github.com/repos/<owner>/<repo>/releases/latest`.

Configure your GitHub repo in `DockLock/Info.plist`:
- `GitHubOwner`
- `GitHubRepo`

When a newer release is detected, DockLock offers to open the release page.

## Notes

- Dock relocation uses an implementation strategy similar to other Dock lock tools: there is no public Apple API for direct display assignment.
- Because this is unsandboxed and intended for source builds/GitHub distribution, it is not App Store-targeted.

## License

MIT (add your preferred license text in `LICENSE`).
