# Maintainer Guide

## Distribution Model

DOCKR uses one user-facing channel: stable GitHub releases.

- End users install from `releases/latest`.
- In-app update checks also target `releases/latest`.
- The app prompts users to restart when an update is ready.

## In-App Update Flow

`GitHubUpdater` checks `https://api.github.com/repos/<owner>/<repo>/releases/latest`.

- Silent check on launch
- Silent check every 15 minutes
- Manual check from menu: `Check for Updates...`
- If newer version exists, menu exposes `Restart to Update (...)`

Update apply path:

1. `DockLock/GitHubUpdater.m` launches `scripts/update-in-place.sh`.
2. `scripts/update-in-place.sh` quits DOCKR.
3. It runs `scripts/install-latest-release.sh` with `OPEN_APP=0`.
4. It reopens `/Applications/DOCKR.app`.

## Required Build Metadata

`DockLock/Info.plist` keys used at runtime:

- `GitHubOwner`
- `GitHubRepo`
- `GitDefaultBranch`
- `CFBundleShortVersionString`

Build with owner/repo set so distributed binaries can self-update:

```bash
DOCKR_GITHUB_OWNER=<github-owner> DOCKR_GITHUB_REPO=DOCKR ./scripts/build.sh
```

Build signing uses a stable designated requirement (`identifier "io.dockr.app"`) so Accessibility trust survives updates better than cdhash-based ad-hoc signatures.

## GitHub Actions

### CI (`.github/workflows/ci.yml`)

- Runs on `main` push and PRs.
- Validates shell script syntax.
- Builds DOCKR.
- Packages release zip artifact.

### Publish (`.github/workflows/publish.yml`)

- Runs on tags matching `v*`.
- Validates tag version equals `DockLock/Info.plist` `CFBundleShortVersionString`.
- Builds app and packages `dist/DOCKR-v<version>-macos.zip`.
- Publishes release assets and SHA256 file.

## Release Checklist

1. Update version in `DockLock/Info.plist`:
   - `CFBundleShortVersionString`
   - `CFBundleVersion`
2. Commit and merge to `main`.
3. Tag and push:

```bash
git tag v<version>
git push origin v<version>
```

4. Verify GitHub release assets exist:
   - `DOCKR-v<version>-macos.zip`
   - `DOCKR-v<tag>-SHA256.txt`

## Permission Recovery

If Accessibility trust appears stale:

```bash
tccutil reset Accessibility io.dockr.app
```

Then relaunch DOCKR and re-grant permission.
