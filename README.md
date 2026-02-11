# DOCKR

<p align="center">
  <img src="assets/dockr-logo.png" alt="DOCKR logo" width="140" />
</p>

DOCKR is a lightweight macOS menu bar app that keeps the Dock anchored to a display you choose.

## Install

### Recommended (stable release)

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_OWNER>/DOCKR/main/scripts/install-latest-release.sh | bash
```

### Development (latest `main`)

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_OWNER>/DOCKR/main/scripts/install-latest-main.sh | bash
```

## First Launch

1. Open `DOCKR`.
2. Grant Accessibility permission when prompted.
3. From the menu bar icon:
   - Enable lock
   - Select target display
   - Use `Relock Now` if needed

## Update

Use the menu bar:

- `Check Stable Updates...` for normal users
- `Check Development Updates (main)...` for early/testing builds

## Known macOS Constraint

For side Dock orientation:

- `left` Dock can only be on displays touching the global far-left edge.
- `right` Dock can only be on displays touching the global far-right edge.

DOCKR marks ineligible displays automatically.

## Troubleshooting

If Accessibility permission appears stale:

```bash
tccutil reset Accessibility io.dockr.app
```

Then reopen `/Applications/DOCKR.app` and re-grant permission.

## Docs

- `docs/MAINTAINER.md` - release workflow, update channel behavior, signing/notarization notes

## License

MIT
