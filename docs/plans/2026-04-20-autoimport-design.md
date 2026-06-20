# AutoImport Design

**Goal:** Build a direct-download macOS app that imports photo and video captures from cameras and removable media without missing vendor-specific files, while presenting an Image Capture-style workflow.

## Product Summary

AutoImport is a macOS utility for ingesting media from mounted cameras, SD cards, and partially discoverable capture devices. The user-visible import unit is a logical capture rather than an individual file. A capture may contain a primary asset, sidecars, proxies, and multipart video segments. The app remembers the last destination, marks already imported captures through in-memory fingerprint validation, and offers deletion from the source only after a complete verified import.

## Platform and Distribution

- Direct-download macOS app.
- Signed and notarized later, but not designed around App Sandbox constraints.
- Native SwiftUI desktop UI with a split-view layout inspired by Image Capture.
- Hybrid discovery: mounted volumes are authoritative when available; `ImageCaptureCore` supplements device discovery.

## Core User Flow

1. The user connects a camera or inserts removable media.
2. The app discovers available sources.
3. The selected source is scanned recursively.
4. Files are grouped into logical captures using vendor-aware and generic heuristics.
5. The app builds an in-memory destination index and marks duplicates.
6. The user imports selected captures into the chosen destination layout.
7. The app offers deletion only for captures that imported successfully in full.

## Source Discovery

### Mounted volumes

- Scan recursively across the full mounted volume, not just `DCIM`.
- Ignore filesystem noise such as `.Trashes`, `.Spotlight-V100`, `.fseventsd`, and similar system paths.
- Continue past unreadable directories and surface warnings without failing the entire scan.

### `ImageCaptureCore`

- Use for discovery and device presence.
- Treat mounted volumes as the authoritative view when the same physical device is also exposed through `ImageCaptureCore`.
- Surface devices with limited raw access as partially readable sources.

## Logical Capture Model

### `SourceDevice`

- Session-local identifier.
- Display name.
- Source type (`mountedVolume`, `imageCaptureDevice`, `folderBookmark`).
- Availability and scan state.
- Source root URL when applicable.
- Capability flags such as browsable, importable, deletable.

### `SourceAssetFile`

- Session-local identifier.
- Source-relative path and absolute URL.
- File size, modification date, media classification, and extension.
- Optional metadata such as duration, pixel size, preview handle.
- Grouping tokens derived from file name and path.

### `LogicalCapture`

- Session-local identifier.
- Display title.
- Representative primary asset.
- Member files, companion files, and multipart segments.
- Capture timestamp.
- Total size.
- Aggregated duration when available.
- Duplicate state, import state, and delete eligibility.

## Grouping and Vendor Rules

- Prefer vendor-specific heuristics for DJI, Insta360, Sony, and other recognized families.
- Fall back to generic filename-family grouping using stem, numeric suffixes, path proximity, and timestamps.
- Multipart recordings are collapsed into one logical capture when naming and timing indicate one continuous recording.
- Unknown files that cannot be attached to a capture are bucketed under hidden `Unknown Folder` containers keyed by parent directory.

## Duplicate Detection

- Destination indexing is in-memory only.
- Matching escalates from cheap metadata to partial hash to full hash.
- File identity is path-independent.
- A capture is considered already imported only when all required member files are matched.
- Partial matches remain importable and are surfaced as incomplete duplicates.

## Import Semantics

- Import operates at capture scope, not per individual file.
- Originals are copied byte-for-byte.
- Each capture is staged and verified before being marked imported.
- Overwrite requires explicit confirmation.
- Unknown folders, when the user opts to reveal them, are copied as folder-preserving imports rather than merged into recognized captures.

## Destination Rules

- The app remembers the last destination path and organization mode.
- Supported layout presets for v1:
  - Flat destination.
  - `YYYY/YYYY-MM-DD`.
  - `Camera Name/YYYY/YYYY-MM-DD`.
- Destination folder naming uses capture metadata when available and falls back to file modification dates.

## Deletion Rules

- Deletion is only offered after a completed import pass.
- Only fully successful captures are eligible.
- The default path should move files to Trash when possible and warn before permanent deletion when not.
- Partial imports are never eligible for deletion.

## UI Layout

- `NavigationSplitView` with native macOS sidebar styling.
- Sidebar lists sources and their states.
- Main pane shows captures in a list-oriented browser first, with grid deferred if needed.
- Bottom control bar includes destination picker, organization mode, selection count, and import actions.
- Detail pane or inspector surfaces preview, member-file breakdown, duplicate explanation, and unknown-folder details.

## Failure Handling

- Source unplug during scan/import should not corrupt completed destination data.
- Destination permission or disk-space failures should stop affected captures cleanly and explain why.
- Cancel stops at a safe boundary, ideally after the active file or capture.
- Completion summary reports imported, skipped, overwritten, failed, and deletable captures.

## V1 Scope Boundaries

- No persistent duplicate database.
- No lossy merge or transcode.
- No background watch/auto-import.
- No cloud destinations.
- No AI features in the critical path.
