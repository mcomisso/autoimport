# AutoImport

<img src="App/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png" alt="AutoImport app icon" width="128">

AutoImport is a native macOS utility for importing photo and video captures from cameras, SD cards, removable drives, and partially discoverable capture devices.

The app works with logical captures instead of individual files. A single capture can include the primary media file, sidecars, proxies, and multipart video segments, so imports are less likely to miss vendor-specific companion files.

## Download

The current release is Developer ID signed, notarized, and published as a DMG:

https://github.com/mcomisso/autoimport/releases/latest

Open the DMG, drag `AutoImport.app` to Applications, and launch it normally. The app requires macOS 15 or later.

## Features

- Discover mounted cameras, SD cards, removable drives, and visible Image Capture devices.
- Recursively scan mounted media while ignoring filesystem noise such as `.Trashes`, `.Spotlight-V100`, and `.fseventsd`.
- Group related files into logical captures, including sidecars, proxies, and multipart clips.
- Detect already imported captures against the selected destination using an in-memory fingerprint index.
- Import selected captures or all captures into flat, date-based, or camera/date destination layouts.
- Surface duplicate, partial duplicate, metadata, capacity, and import progress state in a native SwiftUI interface.
- Offer source deletion only after a capture imported successfully in full.
- Eject mounted source volumes from the sidebar when the source is idle.

## Current Scope

AutoImport is intentionally focused on local ingest. It does not keep a persistent duplicate database, watch devices in the background, transcode media, or import directly into cloud destinations.

The app is distributed outside the Mac App Store and is not sandboxed, matching its removable-media workflow. Release builds use hardened runtime and Developer ID notarization.

## Build From Source

Requirements:

- macOS 15 or later
- Xcode 26.5 or compatible
- XcodeGen

Generate the project:

```bash
xcodegen generate
```

Run the test suite:

```bash
xcodebuild -project AutoImport.xcodeproj -scheme AutoImport -destination 'platform=macOS' test
```

Build and launch a Debug app:

```bash
./script/build_and_run.sh
```

Verify that the app builds and launches:

```bash
./script/build_and_run.sh --verify
```

## Project Layout

- `App/` - app entry point
- `Views/` - SwiftUI desktop interface
- `Stores/` - observable app state and workflow coordination
- `Models/` - source, capture, destination, and import types
- `Services/` - scanning, grouping, duplicate detection, import, deletion, and ejection services
- `Support/` - formatting, classification, preferences, and file helpers
- `AutoImportTests/` - Swift Testing coverage

## Release

The initial public release is `v0.1.0`:

https://github.com/mcomisso/autoimport/releases/tag/v0.1.0

