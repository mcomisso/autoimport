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
        store.selectedCaptureIDs = ["stale", firstCapture.id]

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
        store.selectedCaptureIDs = [firstCapture.id]

        #expect(store.destinationAvailability == .unavailable)
        #expect(!store.canImportSelection)
        #expect(!store.canImportAllCaptures)

        store.destinationURL = destinationURL
        store.captures = [firstCapture]
        store.selectedCaptureIDs = ["stale"]

        #expect(store.destinationAvailability == .reachable)
        #expect(!store.canImportSelection)

        store.selectedCaptureIDs = [firstCapture.id]

        #expect(store.canImportSelection)

        store.isImporting = true

        #expect(!store.canImportSelection)
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
        store.selectedCaptureIDs = ["imported", "failed"]

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
        store.selectedCaptureIDs = [capture.id]

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
        store.selectedCaptureIDs = [videoCapture.id]
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

    private func makeCapture(id: String, memberFiles: [SourceAssetFile] = []) -> LogicalCapture {
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

    private func makeAsset(_ relativePath: String) -> SourceAssetFile {
        let rootURL = URL(fileURLWithPath: "/Volumes/DJI", isDirectory: true)
        let fileURL = rootURL.appending(path: relativePath)

        return SourceAssetFile(
            sourceID: "volume",
            relativePath: relativePath,
            fileURL: fileURL,
            fileSize: 12,
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
