# Maintainer Guide

## Distribution Strategy

DOCKR currently supports two channels:

1. Stable release channel (recommended for users)
2. Main branch channel (advanced/testing)

The app UI defaults to stable updates first to reduce permission churn and update friction.

## Update Scripts

- `scripts/install-latest-release.sh`
  - Downloads latest GitHub release asset (`.zip` or `.dmg`) containing `DOCKR.app`
  - Installs to `/Applications/DOCKR.app`
  - Falls back to `main` installer if no release exists

- `scripts/install-latest-main.sh`
  - Downloads repo source zip from `main`
  - Builds locally
  - Installs to `/Applications/DOCKR.app`

## In-App Update Behavior

`Check Stable Updates...`
- Checks latest release (`/releases/latest`)
- Compares release tag semver to `CFBundleShortVersionString`
- Offers installer run in Terminal

`Check Development Updates (main)...`
- Checks latest commit on configured branch (`GitDefaultBranch`)
- Compares against `BuildGitCommit` in app plist
- Offers main installer run in Terminal

## Build Metadata

`scripts/build.sh` embeds:
- `BuildGitCommit` (short SHA)

Info.plist keys used by updater:
- `GitHubOwner`
- `GitHubRepo`
- `GitDefaultBranch`

## Release Checklist

1. Build app: `scripts/build.sh`
2. Verify install: `scripts/install.sh`
3. Tag version update in `DockLock/Info.plist`:
   - `CFBundleShortVersionString`
   - `CFBundleVersion`
4. Create GitHub release and upload `.zip` or `.dmg` containing `DOCKR.app`

## Signing / Notarization Notes

Without Apple Developer account:
- You can distribute source and unsigned/ad-hoc builds.
- Some users may hit Gatekeeper or Accessibility trust friction.

With Apple Developer account:
- Sign with Developer ID
- Notarize and staple release artifacts
- Best UX for non-technical users

## Common Permission Recovery

If Accessibility trust is stale:

```bash
tccutil reset Accessibility io.dockr.app
```

Then relaunch app and re-grant.
