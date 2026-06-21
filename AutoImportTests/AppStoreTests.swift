import Dispatch
import Foundation
import Testing

@testable import AutoImport

@MainActor
struct AppStoreTests {
    @Test
    func prefersMountedVolumesAndPreselectsOnlyNonDuplicateCaptures() async throws {
        let mountedSource = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let imageCaptureSource = SourceDevice(
            id: "image-capture",
            displayName: "DJI Camera",
            kind: .imageCaptureDevice,
            rootURL: nil,
            subtitle: "Connected",
            state: .ready
        )

        let freshCapture = LogicalCapture(
            id: "fresh",
            displayName: "CLIP_0100",
            primaryAsset: nil,
            memberFiles: [],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
        let duplicateCapture = LogicalCapture(
            id: "duplicate",
            displayName: "CLIP_0101",
            primaryAsset: nil,
            memberFiles: [],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )

        let store = AppStore(
            discoverVolumeSources: { [mountedSource] },
            discoverImageCaptureSources: { [imageCaptureSource] },
            scanSource: { _ in [] },
            groupAssets: { _ in
                CaptureGroupingResult(captures: [freshCapture, duplicateCapture], unknownFolders: [])
            },
            duplicateStateResolver: { captures, _, _, _ in
                Dictionary(uniqueKeysWithValues: captures.map { capture in
                    (capture.id, capture.id == "duplicate" ? .duplicate : .unique)
                })
            },
            importCapturesAction: { _, _, _, _, _, _ in
                ImportSessionResult(captureResults: [])
            },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.refreshSources()
        store.loadSource(mountedSource)
        await store.awaitDuplicateDetection()

        #expect(store.sources.count == 1)
        #expect(store.sources[0].id == "volume")
        #expect(store.selectedCaptureIDs == ["fresh"])
        #expect(store.duplicateState(for: duplicateCapture) == .duplicate)
    }

    @Test
    func refreshSourcesToleratesDuplicateImageCaptureNames() {
        let firstImageCaptureSource = SourceDevice(
            id: "image-capture-a",
            displayName: "DJI Camera",
            kind: .imageCaptureDevice,
            rootURL: nil,
            subtitle: "Connected",
            state: .ready
        )
        let secondImageCaptureSource = SourceDevice(
            id: "image-capture-b",
            displayName: "DJI Camera",
            kind: .imageCaptureDevice,
            rootURL: nil,
            subtitle: "Connected",
            state: .ready
        )
        let mountedSource = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )

        let imageCaptureOnlyStore = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [firstImageCaptureSource, secondImageCaptureSource] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        imageCaptureOnlyStore.refreshSources()

        #expect(imageCaptureOnlyStore.sources.map(\.id) == ["image-capture-a"])

        let mountedVolumeStore = AppStore(
            discoverVolumeSources: { [mountedSource] },
            discoverImageCaptureSources: { [firstImageCaptureSource, secondImageCaptureSource] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        mountedVolumeStore.refreshSources()

        #expect(mountedVolumeStore.sources.map(\.id) == ["volume"])
    }

    @Test
    func persistsDestinationAndOrganizationModeAcrossStoreInstances() {
        let suiteName = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(userDefaults: defaults)
        let destinationURL = URL(fileURLWithPath: "/tmp/AutoImport-Destination")

        let store = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        store.destinationURL = destinationURL
        store.organizationMode = .byCameraAndDate

        let reloadedStore = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        #expect(reloadedStore.destinationURL == destinationURL)
        #expect(reloadedStore.organizationMode == .byCameraAndDate)
    }

    @Test
    func persistsHelperFileVisibilityPreferenceAcrossStoreInstances() {
        let suiteName = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(userDefaults: defaults)

        let store = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        #expect(store.showHelperFiles == false)

        store.showHelperFiles = true

        let reloadedStore = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        #expect(reloadedStore.showHelperFiles == true)
    }

    @Test
    func persistsAutomaticImportPreferenceAcrossStoreInstances() {
        let suiteName = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(userDefaults: defaults)

        let store = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        #expect(store.automaticallyImportDetectedMedia == false)

        store.automaticallyImportDetectedMedia = true

        let reloadedStore = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        #expect(reloadedStore.automaticallyImportDetectedMedia == true)
    }

    @Test
    func automaticImportDoesNotRunByDefaultForDetectedMountedMedia() async throws {
        let suiteName = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let source = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let capture = makeCapture(id: "unique")
        let scanAttemptCount = LockedTestValue(0)
        let importAttemptCount = LockedTestValue(0)
        let store = AppStore(
            preferences: UserPreferences(userDefaults: defaults),
            discoverVolumeSources: { [source] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in
                scanAttemptCount.update { $0 += 1 }
                return []
            },
            groupAssets: { _ in CaptureGroupingResult(captures: [capture], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in
                importAttemptCount.update { $0 += 1 }
                return ImportSessionResult(captureResults: [])
            },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.refreshSourcesAndLoadPreferredSource(preferNewDetectedMedia: true)
        await store.awaitDuplicateDetection()
        await store.awaitAutomaticImport()

        #expect(store.automaticallyImportDetectedMedia == false)
        #expect(store.selectedSource == nil)
        #expect(scanAttemptCount.get() == 0)
        #expect(importAttemptCount.get() == 0)
    }

    @Test
    func automaticImportOnlyImportsUniqueCapturesFromDetectedMountedMedia() async throws {
        let source = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let uniqueCapture = makeCapture(id: "unique")
        let partialCapture = makeCapture(id: "partial")
        let duplicateCapture = makeCapture(id: "duplicate")
        let importedCaptureIDs = LockedTestValue<[String]>([])
        let overwriteValues = LockedTestValue<[Bool]>([])
        let importAttemptCount = LockedTestValue(0)
        let store = AppStore(
            discoverVolumeSources: { [source] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in
                CaptureGroupingResult(
                    captures: [uniqueCapture, partialCapture, duplicateCapture],
                    unknownFolders: []
                )
            },
            duplicateStateResolver: { captures, _, _, _ in
                Dictionary(uniqueKeysWithValues: captures.map { capture in
                    let state: CaptureDuplicateState = switch capture.id {
                    case "partial":
                        .partial
                    case "duplicate":
                        .duplicate
                    default:
                        .unique
                    }
                    return (capture.id, state)
                })
            },
            importCapturesAction: { captures, _, _, _, overwriteDuplicates, _ in
                importAttemptCount.update { $0 += 1 }
                importedCaptureIDs.set(captures.map(\.id))
                overwriteValues.update { $0.append(overwriteDuplicates) }
                return ImportSessionResult(
                    captureResults: captures.map { capture in
                        CaptureImportResult(
                            captureID: capture.id,
                            status: .imported,
                            importedURLs: [],
                            isDeleteEligible: true
                        )
                    }
                )
            },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.automaticallyImportDetectedMedia = true
        store.refreshSourcesAndLoadPreferredSource(preferNewDetectedMedia: true)
        await store.awaitDuplicateDetection()
        await store.awaitAutomaticImport()
        await store.awaitDuplicateDetection()
        await store.awaitAutomaticImport()

        #expect(importAttemptCount.get() == 1)
        #expect(importedCaptureIDs.get() == ["unique"])
        #expect(overwriteValues.get() == [false])
        #expect(store.pendingDeletionCaptureIDs == ["unique"])
    }

    @Test
    func automaticImportIgnoresManualFolderSources() async throws {
        let sourceURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let folderSource = SourceDevice(
            id: "folder",
            displayName: "Source Folder",
            kind: .folderBookmark,
            rootURL: sourceURL,
            subtitle: "Source",
            state: .ready
        )
        let capture = makeCapture(id: "unique")
        let importAttemptCount = LockedTestValue(0)
        let store = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [capture], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in
                importAttemptCount.update { $0 += 1 }
                return ImportSessionResult(captureResults: [])
            },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.automaticallyImportDetectedMedia = true
        store.addFolderSource(folderSource.rootURL!)
        await store.awaitDuplicateDetection()
        await store.awaitAutomaticImport()

        #expect(importAttemptCount.get() == 0)
    }

    @Test
    func selectAllAndClearCaptureSelectionUseCurrentCaptureIDs() {
        let firstCapture = makeCapture(id: "clip-a")
        let secondCapture = makeCapture(id: "clip-b")
        let store = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        store.captures = [firstCapture, secondCapture]
        store.replaceSelectedCaptureIDs(["stale", firstCapture.id])

        #expect(store.selectedCaptureIDs == [firstCapture.id])
        #expect(store.selectedCaptureCount == 1)
        #expect(store.selectedCapturesTotalSize == firstCapture.totalSize)
        #expect(!store.areAllCapturesSelected)
        #expect(store.canSelectAllCaptures)
        #expect(store.canDeselectAllCaptures)

        store.selectAllCaptures()

        #expect(store.selectedCaptureIDs == [firstCapture.id, secondCapture.id])
        #expect(store.areAllCapturesSelected)
        #expect(!store.canSelectAllCaptures)
        #expect(store.canDeselectAllCaptures)

        store.isImporting = true

        #expect(!store.canSelectAllCaptures)
        #expect(!store.canDeselectAllCaptures)

        store.isImporting = false

        store.clearCaptureSelection()

        #expect(store.selectedCaptureIDs.isEmpty)
        #expect(!store.areAllCapturesSelected)
        #expect(store.canSelectAllCaptures)
        #expect(!store.canDeselectAllCaptures)
    }

    @Test
    func togglingMarksUpdatesSelectionTotalsAndIgnoresStaleIDs() {
        let firstCapture = makeCapture(
            id: "clip-a",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_A.MP4", fileSize: 10),
            ]
        )
        let secondCapture = makeCapture(
            id: "clip-b",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_B.MP4", fileSize: 20),
            ]
        )
        let store = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        store.captures = [firstCapture, secondCapture]

        store.setCaptureSelected(id: firstCapture.id, isSelected: true)
        store.setCaptureSelected(id: "missing", isSelected: true)

        #expect(store.selectedCaptureIDs == [firstCapture.id])
        #expect(store.selectedCaptureCount == 1)
        #expect(store.selectedCapturesTotalSize == 10)

        store.toggleMarks(for: [firstCapture.id, secondCapture.id, "missing"])

        #expect(store.selectedCaptureIDs == [firstCapture.id, secondCapture.id])
        #expect(store.selectedCaptureCount == 2)
        #expect(store.selectedCapturesTotalSize == 30)

        store.toggleMarks(for: [firstCapture.id, secondCapture.id])

        #expect(store.selectedCaptureIDs.isEmpty)
        #expect(store.selectedCaptureCount == 0)
        #expect(store.selectedCapturesTotalSize == 0)
    }

    @Test
    func canImportSelectionRequiresReachableDestinationResolvedSelectionAndIdleState() throws {
        let firstCapture = makeCapture(id: "clip-a")
        let store = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL.appending(path: "Missing", directoryHint: .isDirectory)
        store.captures = [firstCapture]
        store.replaceSelectedCaptureIDs([firstCapture.id])

        #expect(store.destinationAvailability == .unavailable)
        #expect(!store.canImportSelection)
        #expect(!store.canImportAllCaptures)

        store.destinationURL = destinationURL
        store.captures = [firstCapture]
        store.replaceSelectedCaptureIDs(["stale"])

        #expect(store.destinationAvailability == .reachable)
        #expect(!store.canImportSelection)

        store.replaceSelectedCaptureIDs([firstCapture.id])

        #expect(store.canImportSelection)

        store.isImporting = true

        #expect(!store.canImportSelection)
    }

    @Test
    func staleSourceLoadCannotOverwriteNewerLoadedSource() async {
        let slowSource = SourceDevice(
            id: "slow",
            displayName: "Slow Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/Slow"),
            subtitle: "Mounted",
            state: .ready
        )
        let fastSource = SourceDevice(
            id: "fast",
            displayName: "Fast Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/Fast"),
            subtitle: "Mounted",
            state: .ready
        )
        let slowScanStarted = DispatchSemaphore(value: 0)
        let releaseSlowScan = DispatchSemaphore(value: 0)
        let store = AppStore(
            discoverVolumeSources: { [slowSource, fastSource] },
            discoverImageCaptureSources: { [] },
            scanSource: { source in
                if source.id == slowSource.id {
                    slowScanStarted.signal()
                    _ = releaseSlowScan.wait(timeout: .now() + 2)
                    return [
                        makeAsset("DCIM/100MEDIA/SLOW.MP4", sourceID: slowSource.id),
                    ]
                }

                return [
                    makeAsset("DCIM/100MEDIA/FAST.MP4", sourceID: fastSource.id),
                ]
            },
            groupAssets: { files in
                guard let sourceID = files.first?.sourceID else {
                    return CaptureGroupingResult(captures: [], unknownFolders: [])
                }

                return CaptureGroupingResult(
                    captures: [makeCapture(id: sourceID, memberFiles: files)],
                    unknownFolders: []
                )
            },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        store.loadSource(slowSource)
        let slowScanStartedResult = await waitForSemaphore(slowScanStarted, timeout: .now() + 2)
        #expect(slowScanStartedResult == .success)

        store.loadSource(fastSource)
        await store.awaitSourceLoading()

        releaseSlowScan.signal()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(store.selectedSource?.id == fastSource.id)
        #expect(store.captureIDs == [fastSource.id])
        #expect(store.selectedCaptureIDs == [fastSource.id])
        #expect(!store.isLoadingSource)
    }

    @Test
    func cancelledImportCannotPublishStaleResultAfterSourceReload() async throws {
        let importingSource = SourceDevice(
            id: "importing",
            displayName: "Importing Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/Importing"),
            subtitle: "Mounted",
            state: .ready
        )
        let replacementSource = SourceDevice(
            id: "replacement",
            displayName: "Replacement Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/Replacement"),
            subtitle: "Mounted",
            state: .ready
        )
        let capture = makeCapture(
            id: "clip-a",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_A.MP4", sourceID: importingSource.id),
            ]
        )
        let importStarted = DispatchSemaphore(value: 0)
        let releaseImport = DispatchSemaphore(value: 0)
        let observedCancellation = LockedTestValue(false)
        let store = AppStore(
            discoverVolumeSources: { [importingSource, replacementSource] },
            discoverImageCaptureSources: { [] },
            scanSource: { source in
                source.id == importingSource.id
                    ? [makeAsset("DCIM/100MEDIA/CLIP_A.MP4", sourceID: importingSource.id)]
                    : []
            },
            groupAssets: { files in
                guard !files.isEmpty else {
                    return CaptureGroupingResult(captures: [], unknownFolders: [])
                }

                return CaptureGroupingResult(captures: [capture], unknownFolders: [])
            },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { captures, _, _, _, _, onProgress in
                importStarted.signal()
                onProgress(ImportProgress(
                    completedCaptures: 0,
                    totalCaptures: captures.count,
                    completedBytes: 0,
                    totalBytes: 1,
                    currentCaptureName: captures.first?.displayName
                ))

                while releaseImport.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
                    if Task.isCancelled {
                        observedCancellation.set(true)
                        throw CancellationError()
                    }
                }

                return ImportSessionResult(
                    captureResults: captures.map { capture in
                        CaptureImportResult(
                            captureID: capture.id,
                            status: .imported,
                            importedURLs: [],
                            isDeleteEligible: true
                        )
                    }
                )
            },
            deleteCaptureFilesAction: { _ in }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.loadSource(importingSource)
        await store.awaitSourceLoading()
        store.replaceSelectedCaptureIDs([capture.id])

        let importTask = Task {
            await store.importSelectedCaptures(overwriteDuplicates: false)
        }
        let importStartedResult = await waitForSemaphore(importStarted, timeout: .now() + 2)
        #expect(importStartedResult == .success)

        store.loadSource(replacementSource)
        for _ in 0..<100 where !observedCancellation.get() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        releaseImport.signal()
        await importTask.value
        await store.awaitSourceLoading()

        #expect(observedCancellation.get())
        #expect(!store.isImporting)
        #expect(store.importProgress == nil)
        #expect(store.lastImportResult == nil)
        #expect(store.pendingDeletionCaptureIDs.isEmpty)
        #expect(store.selectedSource?.id == replacementSource.id)
    }

    @Test
    func tracksOnlySuccessfulImportsForDeletionAndClearsThemAfterDelete() async throws {
        let source = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let importedCapture = LogicalCapture(
            id: "imported",
            displayName: "CLIP_0200",
            primaryAsset: nil,
            memberFiles: [],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
        let failedCapture = LogicalCapture(
            id: "failed",
            displayName: "CLIP_0201",
            primaryAsset: nil,
            memberFiles: [],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )

        let deletedCaptureIDs = LockedTestValue<[String]>([])
        let store = AppStore(
            discoverVolumeSources: { [source] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in
                CaptureGroupingResult(captures: [importedCapture, failedCapture], unknownFolders: [])
            },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { captures, _, _, _, _, _ in
                ImportSessionResult(
                    captureResults: captures.map { capture in
                        CaptureImportResult(
                            captureID: capture.id,
                            status: capture.id == "imported" ? .imported : .failed,
                            importedURLs: [],
                            isDeleteEligible: capture.id == "imported"
                        )
                    }
                )
            },
            deleteCaptureFilesAction: { captures in
                deletedCaptureIDs.set(captures.map(\.id))
            }
        )

        let destinationURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        store.destinationURL = destinationURL
        store.refreshSources()
        store.loadSource(source)
        await store.awaitSourceLoading()
        store.replaceSelectedCaptureIDs(["imported", "failed"])

        await store.importSelectedCaptures(overwriteDuplicates: false)

        #expect(store.pendingDeletionCaptureIDs == ["imported"])

        await store.deleteImportedCapturesFromSource()

        #expect(deletedCaptureIDs.get() == ["imported"])
        #expect(store.pendingDeletionCaptureIDs.isEmpty)
    }

    @Test
    func persistedUnavailableDestinationStaysVisibleButBlocksImports() {
        let suiteName = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(userDefaults: defaults)
        let missingDestinationURL = FileManager.default.temporaryDirectory
            .appending(path: "AutoImport-Missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        preferences.saveDestinationURL(missingDestinationURL)

        let capture = makeCapture(id: "clip-a")
        let store = AppStore(
            preferences: preferences,
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in }
        )

        store.captures = [capture]
        store.replaceSelectedCaptureIDs([capture.id])

        #expect(store.destinationURL == missingDestinationURL)
        #expect(store.destinationAvailability == .unavailable)
        #expect(!store.canImportSelection)
        #expect(!store.canImportAllCaptures)
    }

    @Test
    func clearSidecarFilesFromSelectedSourceDeletesOnlySidecarFilesAndReloads() async {
        let source = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let scannedFiles = [
            makeAsset("DCIM/100MEDIA/CLIP_0001.MP4"),
            makeAsset("DCIM/100MEDIA/CLIP_0001.THM"),
            makeAsset("DCIM/100MEDIA/CLIP_0001.XML"),
            makeAsset("MISC/DEBUG.BIN"),
        ]

        let scanCount = LockedTestValue(0)
        let deletedRelativePaths = LockedTestValue<[String]>([])
        let store = AppStore(
            discoverVolumeSources: { [source] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in
                scanCount.update { $0 += 1 }
                return scannedFiles
            },
            groupAssets: { CaptureGrouper().group($0) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in },
            deleteSourceFilesAction: { files in
                deletedRelativePaths.set(files.map(\.relativePath))
            }
        )

        store.refreshSources()
        store.loadSource(source)
        await store.awaitSourceLoading()

        #expect(store.canClearSidecarFiles)
        #expect(store.sidecarFilesInSelectedSource.map(\.relativePath) == [
            "DCIM/100MEDIA/CLIP_0001.THM",
            "DCIM/100MEDIA/CLIP_0001.XML",
        ])

        await store.clearSidecarFilesFromSelectedSource()
        await store.awaitSourceLoading()

        #expect(deletedRelativePaths.get() == [
            "DCIM/100MEDIA/CLIP_0001.THM",
            "DCIM/100MEDIA/CLIP_0001.XML",
        ])
        #expect(scanCount.get() == 2)
    }

    @Test
    func deleteCapturesFromSourceDeletesRequestedCaptureMembersAndReloads() async {
        let source = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let requestedCapture = makeCapture(
            id: "clip-a",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_A.MP4"),
                makeAsset("DCIM/100MEDIA/CLIP_A.THM"),
            ]
        )
        let otherCapture = makeCapture(
            id: "clip-b",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_B.MP4"),
            ]
        )

        let scanCount = LockedTestValue(0)
        let deletedCaptureIDs = LockedTestValue<[String]>([])
        let deletedRelativePaths = LockedTestValue<[String]>([])
        let store = AppStore(
            discoverVolumeSources: { [source] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in
                scanCount.update { $0 += 1 }
                return []
            },
            groupAssets: { _ in
                CaptureGroupingResult(captures: [requestedCapture, otherCapture], unknownFolders: [])
            },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { captures in
                deletedCaptureIDs.set(captures.map(\.id))
                deletedRelativePaths.set(captures.flatMap { $0.memberFiles.map(\.relativePath) })
            }
        )

        store.refreshSources()
        store.loadSource(source)
        await store.awaitSourceLoading()

        await store.deleteCapturesFromSource(ids: ["clip-a", "missing"])
        await store.awaitSourceLoading()

        #expect(deletedCaptureIDs.get() == ["clip-a"])
        #expect(deletedRelativePaths.get() == [
            "DCIM/100MEDIA/CLIP_A.MP4",
            "DCIM/100MEDIA/CLIP_A.THM",
        ])
        #expect(scanCount.get() == 2)
    }

    @Test
    func deleteCapturesFromSourceSkipsEmptyAndBusyCaptures() async {
        let emptyCapture = makeCapture(id: "empty")
        let videoCapture = makeCapture(
            id: "clip-a",
            memberFiles: [
                makeAsset("DCIM/100MEDIA/CLIP_A.MP4"),
            ]
        )
        let deletedCaptureIDs = LockedTestValue<[String]>([])
        let store = AppStore(
            discoverVolumeSources: { [] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { captures in
                deletedCaptureIDs.set(captures.map(\.id))
            }
        )

        store.captures = [emptyCapture]

        #expect(!store.canDeleteCaptureFromSource(id: emptyCapture.id))

        await store.deleteCapturesFromSource(ids: [emptyCapture.id])

        #expect(deletedCaptureIDs.get().isEmpty)

        store.captures = [videoCapture]
        store.replaceSelectedCaptureIDs([videoCapture.id])
        store.pendingDeletionCaptureIDs = [videoCapture.id]
        store.isImporting = true

        #expect(!store.canDeleteCaptureFromSource(id: videoCapture.id))

        await store.deleteCapturesFromSource(ids: [videoCapture.id])

        #expect(deletedCaptureIDs.get().isEmpty)

        store.isImporting = false

        #expect(store.canDeleteCaptureFromSource(id: videoCapture.id))

        await store.deleteCapturesFromSource(ids: [videoCapture.id])

        #expect(deletedCaptureIDs.get() == [videoCapture.id])
        #expect(store.selectedCaptureIDs.isEmpty)
        #expect(store.pendingDeletionCaptureIDs.isEmpty)
    }

    @Test
    func ejectSourceEjectsMountedVolumeRefreshesSourcesAndLoadsNextSelection() async {
        let mountedSource = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )
        let imageCaptureSource = SourceDevice(
            id: "image-capture",
            displayName: "DJI Camera",
            kind: .imageCaptureDevice,
            rootURL: nil,
            subtitle: "Connected",
            state: .ready
        )

        let discoveredVolumeSources = LockedTestValue<[SourceDevice]>([mountedSource])
        let ejectedSourceIDs = LockedTestValue<[String]>([])
        let scannedSourceIDs = LockedTestValue<[String]>([])
        let store = AppStore(
            discoverVolumeSources: { discoveredVolumeSources.get() },
            discoverImageCaptureSources: { [imageCaptureSource] },
            scanSource: { source in
                scannedSourceIDs.update { $0.append(source.id) }
                return []
            },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in },
            ejectSourceAction: { source in
                ejectedSourceIDs.update { $0.append(source.id) }
                discoveredVolumeSources.set([])
            }
        )

        store.refreshSources()
        store.loadSource(mountedSource)
        await store.awaitSourceLoading()

        #expect(store.canEjectSource(mountedSource))

        await store.ejectSource(mountedSource)
        await store.awaitSourceLoading()

        #expect(ejectedSourceIDs.get() == ["volume"])
        #expect(store.ejectingSourceID == nil)
        #expect(store.sourceEjectionErrorMessage == nil)
        #expect(store.sources.map(\.id) == ["image-capture"])
        #expect(store.selectedSource?.id == "image-capture")
        #expect(scannedSourceIDs.get() == ["volume", "image-capture"])
    }

    @Test
    func ejectSourceSkipsUnsupportedSourcesBusyStateAndReportsFailures() async {
        let folderSource = SourceDevice(
            id: "folder",
            displayName: "Downloads",
            kind: .folderBookmark,
            rootURL: URL(fileURLWithPath: "/Users/example/Downloads"),
            subtitle: "Downloads",
            state: .ready
        )
        let volumeSource = SourceDevice(
            id: "volume",
            displayName: "DJI Camera",
            kind: .mountedVolume,
            rootURL: URL(fileURLWithPath: "/Volumes/DJI"),
            subtitle: "Mounted",
            state: .ready
        )

        let ejectAttemptCount = LockedTestValue(0)
        let store = AppStore(
            discoverVolumeSources: { [volumeSource] },
            discoverImageCaptureSources: { [] },
            scanSource: { _ in [] },
            groupAssets: { _ in CaptureGroupingResult(captures: [], unknownFolders: []) },
            duplicateStateResolver: { _, _, _, _ in [:] },
            importCapturesAction: { _, _, _, _, _, _ in ImportSessionResult(captureResults: []) },
            deleteCaptureFilesAction: { _ in },
            ejectSourceAction: { _ in
                ejectAttemptCount.update { $0 += 1 }
                throw VolumeEjectionError.unsupportedSource
            }
        )

        #expect(!store.canEjectSource(folderSource))

        await store.ejectSource(folderSource)

        #expect(ejectAttemptCount.get() == 0)

        store.isImporting = true

        #expect(!store.canEjectSource(volumeSource))

        await store.ejectSource(volumeSource)

        #expect(ejectAttemptCount.get() == 0)

        store.isImporting = false

        await store.ejectSource(volumeSource)

        #expect(ejectAttemptCount.get() == 1)
        #expect(store.ejectingSourceID == nil)
        #expect(store.sourceEjectionErrorMessage == "Only mounted source drives can be ejected.")

        store.dismissSourceEjectionError()

        #expect(store.sourceEjectionErrorMessage == nil)
    }

    nonisolated private func makeCapture(id: String, memberFiles: [SourceAssetFile] = []) -> LogicalCapture {
        LogicalCapture(
            id: id,
            displayName: id,
            primaryAsset: memberFiles.first { $0.classification != .sidecar } ?? memberFiles.first,
            memberFiles: memberFiles,
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
    }

    nonisolated private func makeAsset(
        _ relativePath: String,
        sourceID: String = "volume",
        fileSize: Int64 = 12
    ) -> SourceAssetFile {
        let rootURL = URL(fileURLWithPath: "/Volumes/DJI", isDirectory: true)
        let fileURL = rootURL.appending(path: relativePath)

        return SourceAssetFile(
            sourceID: sourceID,
            relativePath: relativePath,
            fileURL: fileURL,
            fileSize: fileSize,
            modificationDate: .distantPast,
            classification: .classify(pathExtension: fileURL.pathExtension),
            duration: nil,
            pixelSize: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AutoImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private func waitForSemaphore(
        _ semaphore: DispatchSemaphore,
        timeout: DispatchTime
    ) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: semaphore.wait(timeout: timeout))
            }
        }
    }
}

private final class LockedTestValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func update(_ transform: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&value)
    }
}
