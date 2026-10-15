# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Thumbnail strip along the bottom of the window showing every file in the
  folder, with the current one highlighted; click a thumbnail to jump to it.
  Toggle with `T` or View › Hide/Show Thumbnails (`⌥⌘T`); the choice is
  remembered. Shown only when the folder has more than one file. Thumbnails
  are rendered by Quick Look for the visible part of the strip only.

## [1.5.0] - 2026-08-01

### Changed

- Bundle identifier is now `com.richardogcc.mviewer` (was `com.grcm.mviewer`).
  macOS treats this as a new app, so any per-app permissions tied to the old
  identifier reset after updating.
- License holder unified as `richardogcc`; repo standardized to the shared
  macOS utilities convention: `VERSION` file, `scripts/` layout
  (build_app/make_icon/release), and `app-manifest.json` for discovery by the
  MLauncher orchestrator.
- Releases are packaged as `MViewer-<version>.dmg` by `scripts/release.sh`.

## [1.4.2] and earlier

No detailed changelog was kept before 1.5.0. Feature summary of the app as of
this point:

- Fast native image and video viewer for macOS built with pure Swift + AppKit
  and zero dependencies; decodes with the system's ImageIO and AVFoundation.
- Support for every format macOS knows: images (JPG, PNG, GIF, WebP, TIFF,
  HEIC/HEIF, AVIF, BMP, PSD, EXR, JPEG 2000...), camera RAW (NEF, ARW, CR2/CR3,
  RAF, ORF, RW2, DNG, PEF, SRW...), animated images (GIF, animated WebP, APNG)
  and video (MP4, MOV, M4V, 3GP, MTS/M2TS).
- Instant open: shows the file's embedded preview (RAW in-file JPEG) or a
  downsampled decode immediately, then swaps in the full-resolution image in
  the background without touching the zoom.
- Folder browsing with the arrow keys, with prefetching of neighboring files
  backed by an in-memory cache, and a counter pill showing the position in the
  folder (auto-hidden after inactivity).
- Zoom controls: fit, actual size, keyboard/scroll/pinch zoom, double-click
  toggle; window opens maximized and small images are stretched to fill.
- Info sidebar (Cmd+I): file details, image properties, camera EXIF, GPS
  position with a mini map that opens the spot in Maps, and a full raw
  metadata dump; resizable, follows along while browsing.
- 360-degree video detection (Spherical Video metadata) with immersive
  playback inside a sphere: drag to look around, scroll to zoom, playback
  controls bar, manual toggle with the `3` key.
- Video playback with play/pause, persistent volume and mute across videos
  and launches, and no audio overlap when switching between videos.
- Context menu (Show in Finder, Copy Image, Get Info, Move to Trash),
  drag & drop of files or folders, command-line opening, copy to clipboard,
  move to Trash, full screen, keyboard shortcuts overlay and About overlay.
