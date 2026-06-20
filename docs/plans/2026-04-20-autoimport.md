# AutoImport Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a runnable direct-download macOS app that scans mounted media, groups files into logical captures, detects duplicates in-memory, imports selected captures, and presents the workflow in an Image Capture-style SwiftUI shell.

**Architecture:** Use an Xcode-generated SwiftUI macOS app with a thin app shell, deterministic domain/services layer, and `Swift Testing` coverage around grouping, fingerprint matching, and import orchestration. Mounted-volume scanning is the primary ingestion path; `ImageCaptureCore` discovery is additive and non-authoritative when a volume is already visible.

**Tech Stack:** Swift 6.3, SwiftUI, Observation, Foundation, AVFoundation, QuickLookThumbnailing, UniformTypeIdentifiers, ImageCaptureCore, Swift Testing, XcodeGen, xcodebuild.

---

### Task 1: Scaffold The Project

**Files:**
- Create: `project.yml`
- Create: `App/AutoImportApp.swift`
- Create: `Views/ContentView.swift`
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

**Step 1: Create the project definition**

- Define one macOS application target and one test target in `project.yml`.
- Set bundle identifier, deployment target, generated Info.plist, and source/test folders.

**Step 2: Generate the Xcode project**

Run: `xcodegen generate`
Expected: `AutoImport.xcodeproj` created successfully

**Step 3: Add the minimal app entrypoint**

- Add a SwiftUI `@main` app.
- Add a root `ContentView` with placeholder split-view structure.

**Step 4: Add build/run tooling**

- Write `script/build_and_run.sh` to build with `xcodebuild`, kill any running app instance, and launch the built `.app`.
- Wire `.codex/environments/environment.toml` to `./script/build_and_run.sh`.

**Step 5: Verify the scaffold builds**

Run: `./script/build_and_run.sh --verify`
Expected: build succeeds and the `AutoImport` process is running

### Task 2: Create Domain Models And Grouping Tests

**Files:**
- Create: `Models/SourceDevice.swift`
- Create: `Models/SourceAssetFile.swift`
- Create: `Models/LogicalCapture.swift`
- Create: `Support/MediaClassification.swift`
- Test: `AutoImportTests/CaptureGroupingTests.swift`

**Step 1: Write the failing grouping test**

- Cover grouping of files with the same basename into one logical capture.
- Cover multipart aggregation into one capture with combined segment count.
- Cover unknown-file bucketing.

**Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/CaptureGroupingTests`
Expected: FAIL because the domain models and grouper do not exist yet

**Step 3: Write the minimal grouping implementation**

- Add the domain models.
- Add vendor-agnostic grouping tokens and unknown-folder support.

**Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/CaptureGroupingTests`
Expected: PASS

### Task 3: Implement Recursive Volume Scanning

**Files:**
- Create: `Services/VolumeSourceScanner.swift`
- Create: `Support/DirectoryFilter.swift`
- Test: `AutoImportTests/VolumeSourceScannerTests.swift`

**Step 1: Write the failing scanner test**

- Build temporary folder fixtures containing media files, ignored system paths, and unknown folders.
- Assert recursive discovery and ignore behavior.

**Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/VolumeSourceScannerTests`
Expected: FAIL because the scanner does not exist

**Step 3: Write the minimal scanner**

- Enumerate files recursively.
- Ignore configured noise directories.
- Return `SourceAssetFile` values with basic metadata.

**Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/VolumeSourceScannerTests`
Expected: PASS

### Task 4: Implement Duplicate Detection

**Files:**
- Create: `Services/DestinationFingerprintIndex.swift`
- Create: `Support/FileFingerprint.swift`
- Test: `AutoImportTests/DestinationFingerprintIndexTests.swift`

**Step 1: Write the failing duplicate tests**

- Cover exact duplicates, same-name-different-content, and partial family matches.

**Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/DestinationFingerprintIndexTests`
Expected: FAIL because the index and fingerprint types do not exist

**Step 3: Write the minimal implementation**

- Add tiered comparison based on metadata, partial hash, then full hash.
- Add capture-level duplicate derivation.

**Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/DestinationFingerprintIndexTests`
Expected: PASS

### Task 5: Implement Import Orchestration

**Files:**
- Create: `Services/ImportCoordinator.swift`
- Create: `Models/ImportResult.swift`
- Test: `AutoImportTests/ImportCoordinatorTests.swift`

**Step 1: Write the failing import tests**

- Cover successful capture import, overwrite confirmation path, partial failure behavior, and delete-eligibility results.

**Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/ImportCoordinatorTests`
Expected: FAIL because import orchestration does not exist

**Step 3: Write the minimal implementation**

- Copy member files per capture.
- Stage outputs safely.
- Return per-capture outcomes and delete eligibility.

**Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/ImportCoordinatorTests`
Expected: PASS

### Task 6: Build The App State And Discovery Layer

**Files:**
- Create: `Stores/AppStore.swift`
- Create: `Services/VolumeDiscoveryService.swift`
- Create: `Services/ImageCaptureDiscoveryService.swift`
- Create: `Support/UserPreferences.swift`

**Step 1: Write the failing store/discovery tests**

- Cover remembered destination preferences and source list refresh behavior where testable.

**Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/AppStoreTests`
Expected: FAIL because the store does not exist

**Step 3: Write the minimal implementation**

- Build observable app state for sources, captures, selection, and preferences.
- Add a mounted-volume discovery service.
- Add a first-pass `ImageCaptureCore` bridge for visible device names and states.

**Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport -only-testing:AutoImportTests/AppStoreTests`
Expected: PASS

### Task 7: Build The SwiftUI Shell

**Files:**
- Modify: `Views/ContentView.swift`
- Create: `Views/SidebarView.swift`
- Create: `Views/CaptureListView.swift`
- Create: `Views/CaptureRowView.swift`
- Create: `Views/InspectorView.swift`
- Create: `Views/DestinationToolbarView.swift`

**Step 1: Write a small view-state test where practical**

- Add deterministic tests for formatting/presentation helpers.

**Step 2: Build the split-view UI**

- Sidebar with sources and states.
- List browser with duplicate dimming and multipart badges.
- Inspector for preview metadata and member files.
- Bottom controls for destination and import actions.

**Step 3: Run a build verification**

Run: `./script/build_and_run.sh --verify`
Expected: app launches successfully

### Task 8: End-To-End Verification

**Files:**
- Modify as needed based on failures

**Step 1: Run the full test suite**

Run: `xcodebuild test -project AutoImport.xcodeproj -scheme AutoImport`
Expected: PASS

**Step 2: Run the app**

Run: `./script/build_and_run.sh --verify`
Expected: PASS with running app process

**Step 3: Smoke-test a sample folder import**

- Use a temporary source folder fixture with grouped media, duplicate destination content, and unknown items.
- Verify scan, selection, import, and delete eligibility summary.

**Step 4: Commit**

```bash
git add .
git commit -m "feat: scaffold AutoImport macOS app"
```
