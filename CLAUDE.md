# MViewer — project conventions

MViewer is one of a family of small macOS utility apps that share the same
conventions. Follow them exactly.

## License and language

- License: MIT, copyright holder exactly `richardogcc` (`Copyright (c) 2026 richardogcc`).
- Everything is in English: README, UI strings, code comments, commit messages.

## Identity

- Bundle ID scheme: `com.richardogcc.<lowercased-app-name>` → `com.richardogcc.mviewer`.
- `app-manifest.json` at the repo root describes the app for a future
  orchestrator app (discovery/auto-update): name, bundleId, one-line English
  description, `repo` (`richardogcc/MViewer`), `minMacOS`, and the release
  `artifact` name pattern (`MViewer-{version}.dmg`). Keep it in sync with
  Info.plist and the release scripts.

## Toolchain

- `Package.swift` uses `// swift-tools-version: 6.0` and platforms `.macOS(.v14)`.
- If Swift 6 language mode causes extensive concurrency errors, keep tools 6.0
  but add `swiftSettings: [.swiftLanguageMode(.v5)]` to the target instead of
  doing a large refactor.

## Versioning

- `VERSION` at the repo root holds the plain semver version; it is the single
  source of truth. `scripts/build_app.sh` injects it into Info.plist
  (`__VERSION__` placeholders) at build time.
- `CHANGELOG.md` follows the Keep a Changelog format. Every user-facing change
  gets an entry; the entry for the version being released becomes the GitHub
  release notes.

## Scripts (`scripts/`)

- `build_app.sh` — builds `build/MViewer.app` from a `swift build -c release`
  binary, injects Info.plist with the version from `VERSION`, copies
  `Resources/AppIcon.icns`.
- `make_icon.swift` — regenerates the app icon programmatically. The app must
  always have `Resources/AppIcon.icns`.
- `release.sh` — builds the app, packages `MViewer-<VERSION>.dmg` via hdiutil
  into `dist/`, then creates a GitHub release
  (`gh release create v$VERSION dist/MViewer-$VERSION.dmg`) with notes from
  the CHANGELOG entry.

## Release flow

1. Bump `VERSION`, add the `CHANGELOG.md` entry.
2. Run `scripts/release.sh`. Releases are pushed manually from this machine —
   never create a GitHub release or push on the user's behalf.

## Git

- Never push; the user pushes.
- Commit when a change is done. Commit messages in English, ending with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Never commit build artifacts (`.build/`, `build/`, `dist/`, `*.dmg`, `.DS_Store`).
