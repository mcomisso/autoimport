import Foundation
import Observation

struct CaptureRowPresentation: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let duplicateState: CaptureDuplicateState
    let kindText: String
    let timestampText: String
    let sizeText: String
    let statusText: String
    let detailTexts: [String]
    let thumbnailFileURL: URL?
    let previewFileURL: URL?
    let canOpen: Bool
    let canRevealInFinder: Bool
    let canCopyFilePath: Bool
    let captureSortValue: String
    let kindSortValue: String
    let modificationDateSortValue: Date
    let sizeSortValue: Int64
    let statusSortValue: String

    init(capture: LogicalCapture, duplicateState: CaptureDuplicateState) {
        self.init(
            id: capture.id,
            displayName: capture.displayName,
            duplicateState: duplicateState,
            kindText: Self.kindText(for: capture),
            timestampText: CaptureDisplayFormatter.timestamp(capture.primaryAsset?.modificationDate) ?? "-",
            sizeText: CaptureDisplayFormatter.fileSize(capture.totalSize),
            statusText: Self.statusText(for: capture, duplicateState: duplicateState),
            detailTexts: Self.detailTexts(for: capture),
            thumbnailFileURL: capture.preferredThumbnailAsset?.fileURL,
            previewFileURL: capture.preferredPreviewAsset?.fileURL,
            canOpen: capture.fileActionURL != nil,
            canRevealInFinder: !capture.finderSelectionURLs.isEmpty,
            canCopyFilePath: capture.fileActionURL != nil,
            captureSortValue: Self.normalizedSortValue(capture.displayName),
            kindSortValue: Self.normalizedSortValue(Self.kindText(for: capture)),
            modificationDateSortValue: capture.primaryAsset?.modificationDate ?? .distantPast,
            sizeSortValue: capture.totalSize,
            statusSortValue: Self.normalizedSortValue(Self.statusText(for: capture, duplicateState: duplicateState))
        )
    }

    init(
        id: String,
        displayName: String,
        duplicateState: CaptureDuplicateState,
        kindText: String,
        timestampText: String,
        sizeText: String,
        statusText: String,
        detailTexts: [String],
        thumbnailFileURL: URL? = nil,
        previewFileURL: URL? = nil,
        canOpen: Bool = false,
        canRevealInFinder: Bool = false,
        canCopyFilePath: Bool = false,
        captureSortValue: String? = nil,
        kindSortValue: String? = nil,
        modificationDateSortValue: Date = .distantPast,
        sizeSortValue: Int64 = 0,
        statusSortValue: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.duplicateState = duplicateState
        self.kindText = kindText
        self.timestampText = timestampText
        self.sizeText = sizeText
        self.statusText = statusText
        self.detailTexts = detailTexts
        self.thumbnailFileURL = thumbnailFileURL
        self.previewFileURL = previewFileURL
        self.canOpen = canOpen
        self.canRevealInFinder = canRevealInFinder
        self.canCopyFilePath = canCopyFilePath
        self.captureSortValue = captureSortValue ?? Self.normalizedSortValue(displayName)
        self.kindSortValue = kindSortValue ?? Self.normalizedSortValue(kindText)
        self.modificationDateSortValue = modificationDateSortValue
        self.sizeSortValue = sizeSortValue
        self.statusSortValue = statusSortValue ?? Self.normalizedSortValue(statusText)
    }

    init(
        capture: LogicalCapture,
        duplicateState: CaptureDuplicateState,
        kindText: String,
        timestampText: String,
        sizeText: String,
        statusText: String,
        detailTexts: [String]
    ) {
        self.init(
            id: capture.id,
            displayName: capture.displayName,
            duplicateState: duplicateState,
            kindText: kindText,
            timestampText: timestampText,
            sizeText: sizeText,
            statusText: statusText,
            detailTexts: detailTexts,
            thumbnailFileURL: capture.preferredThumbnailAsset?.fileURL,
            previewFileURL: capture.preferredPreviewAsset?.fileURL,
            canOpen: capture.fileActionURL != nil,
            canRevealInFinder: !capture.finderSelectionURLs.isEmpty,
            canCopyFilePath: capture.fileActionURL != nil,
            modificationDateSortValue: capture.primaryAsset?.modificationDate ?? .distantPast,
            sizeSortValue: capture.totalSize
        )
    }

    var isDuplicate: Bool {
        duplicateState == .duplicate
    }

    private static func kindText(for capture: LogicalCapture) -> String {
        switch capture.primaryAsset?.classification {
        case .image:
            return "Photo"
        case .video:
            return "Video"
        case .sidecar:
            return "Sidecar"
        case .unknown, .none:
            return "Capture"
        }
    }

    private static func statusText(
        for capture: LogicalCapture,
        duplicateState: CaptureDuplicateState
    ) -> String {
        if let duplicateStatus = CaptureDisplayFormatter.duplicateStatus(duplicateState) {
            return duplicateStatus
        }

        return CaptureDisplayFormatter.multipartSummary(
            segmentCount: capture.multipartSegments.count,
            totalDuration: capture.totalDuration
        ) ?? "Ready"
    }

    private static func detailTexts(for capture: LogicalCapture) -> [String] {
        var texts: [String] = []

        if let multipartSummary = CaptureDisplayFormatter.multipartSummary(
            segmentCount: capture.multipartSegments.count,
            totalDuration: capture.totalDuration
        ) {
            texts.append(multipartSummary)
        } else if let duration = capture.totalDuration {
            texts.append(CaptureDisplayFormatter.duration(duration))
        }

        texts.append(CaptureDisplayFormatter.fileSize(capture.totalSize))

        if let timestamp = CaptureDisplayFormatter.timestamp(capture.primaryAsset?.modificationDate) {
            texts.append(timestamp)
        }

        return texts
    }

    private static func normalizedSortValue(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct AutomaticImportAttemptKey: Hashable, Sendable {
    let sourceID: String
    let destinationPath: String
    let organizationModeRawValue: String
    let captureIDs: [String]
}

private struct CaptureCacheSnapshot: Sendable {
    let captures: [LogicalCapture]
    let captureIDs: [String]
    let captureByID: [String: LogicalCapture]
    let captureSizeByID: [String: Int64]
    let sidecarFilesInSelectedSource: [SourceAssetFile]
    let captureRows: [CaptureRowPresentation]

    init(
        captures: [LogicalCapture],
        duplicateStatesByCaptureID: [String: CaptureDuplicateState]
    ) {
        self.captures = captures
        self.captureIDs = captures.map(\.id)
        self.captureByID = Dictionary(captures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.captureSizeByID = Dictionary(captures.map { ($0.id, $0.totalSize) }, uniquingKeysWith: { first, _ in first })
        self.sidecarFilesInSelectedSource = captures
            .flatMap(\.memberFiles)
            .filter(\.isHelperFile)
            .sorted { $0.relativePath < $1.relativePath }
        self.captureRows = captures.map { capture in
            CaptureRowPresentation(
                capture: capture,
                duplicateState: duplicateStatesByCaptureID[capture.id] ?? .unique
            )
        }
    }
}

private struct LoadedSourceSnapshot: Sendable {
    let captureCache: CaptureCacheSnapshot
    let unknownFolders: [UnknownFolder]

    init(grouping: CaptureGroupingResult) {
        self.captureCache = CaptureCacheSnapshot(
            captures: grouping.captures,
            duplicateStatesByCaptureID: [:]
        )
        self.unknownFolders = grouping.unknownFolders
    }
}

private struct SelectionSummary: Equatable, Sendable {
    var count: Int
    var totalSize: Int64
    var duplicateCount: Int
    var partialDuplicateCount: Int
}

@MainActor
@Observable
final class AppStore {
    typealias DiscoverVolumeSourcesAction = @Sendable () -> [SourceDevice]
    typealias DiscoverImageCaptureSourcesAction = @MainActor () -> [SourceDevice]
    typealias ScanSourceAction = @Sendable (SourceDevice) -> [SourceAssetFile]
    typealias GroupAssetsAction = @Sendable ([SourceAssetFile]) -> CaptureGroupingResult
    typealias DuplicateStateResolver = @Sendable ([LogicalCapture], URL, DestinationOrganizationMode, String) async -> [String: CaptureDuplicateState]
    typealias ImportProgressHandler = @Sendable (ImportProgress) -> Void
    typealias ImportCapturesAction = @Sendable ([LogicalCapture], URL, DestinationOrganizationMode, String, Bool, @escaping ImportProgressHandler) throws -> ImportSessionResult
    typealias DeleteCaptureFilesAction = @Sendable ([LogicalCapture]) async -> Void
    typealias DeleteSourceFilesAction = @Sendable ([SourceAssetFile]) async -> Void
    typealias EjectSourceAction = @Sendable (SourceDevice) async throws -> Void

    private let preferences: UserPreferences
    private let discoverVolumeSources: DiscoverVolumeSourcesAction
    private let discoverImageCaptureSources: DiscoverImageCaptureSourcesAction
    private let scanSource: ScanSourceAction
    private let groupAssets: GroupAssetsAction
    private let duplicateStateResolver: DuplicateStateResolver
    private let importCapturesAction: ImportCapturesAction
    private let deleteCaptureFilesAction: DeleteCaptureFilesAction
    private let deleteSourceFilesAction: DeleteSourceFilesAction
    private let ejectSourceAction: EjectSourceAction
    let mediaProcessingTracker: MediaProcessingTracker

    private var folderSources: [SourceDevice] = []
    private var duplicateStatesByCaptureID: [String: CaptureDuplicateState] = [:]
    private var sourceRefreshTask: Task<Void, Never>?
    private var sourceRefreshGeneration = 0
    private var sourceLoadingTask: Task<Void, Never>?
    private var sourceLoadingGeneration = 0
    private var duplicateDetectionTask: Task<Void, Never>?
    private var duplicateDetectionGeneration = 0
    private var duplicateStatesAreResolved = false
    private var pendingNonDuplicatePreselection = false
    private var automaticImportTask: Task<Void, Never>?
    private var lastAutomaticImportAttemptKey: AutomaticImportAttemptKey?
    private var importWorkerTask: Task<ImportSessionResult, Never>?
    private var importGeneration = 0
    private var activeImportGeneration: Int?
    private var destinationAvailabilityTask: Task<Void, Never>?
    private var destinationAvailabilityGeneration = 0
    private var destinationCapacityTask: Task<Void, Never>?
    private var destinationCapacityGeneration = 0
    private var sourceEjectionTask: Task<Void, Never>?
    private var isApplyingCaptureCacheSnapshot = false

    @ObservationIgnored private var captureByID: [String: LogicalCapture] = [:]
    @ObservationIgnored private var captureSizeByID: [String: Int64] = [:]
    @ObservationIgnored private var selectedCaptureIDSet: Set<String> = []

    var sources: [SourceDevice] = []
    var selectedSource: SourceDevice?
    var captures: [LogicalCapture] = [] {
        didSet {
            guard !isApplyingCaptureCacheSnapshot else {
                return
            }

            rebuildCaptureCaches()
        }
    }
    private(set) var captureIDs: [String] = []
    private(set) var captureRows: [CaptureRowPresentation] = []
    var unknownFolders: [UnknownFolder] = []
    private(set) var selectedCaptureIDs: [String] = []
    private(set) var selectedCaptureCount = 0
    private(set) var selectedCapturesTotalSize: Int64 = 0
    private(set) var selectedDuplicateCaptureCount = 0
    private(set) var selectedPartialDuplicateCaptureCount = 0
    private(set) var sidecarFilesInSelectedSource: [SourceAssetFile] = []
    var pendingDeletionCaptureIDs: [String] = []
    var showUnknownFolders = false
    var lastImportResult: ImportSessionResult?
    var isLoadingSource = false
    var isImporting = false
    var importProgress: ImportProgress?
    var ejectingSourceID: String?
    var sourceEjectionErrorMessage: String?
    private(set) var destinationCapacity: DestinationCapacity?
    private(set) var destinationAvailability: DestinationAvailability = .notSelected
    var showHelperFiles: Bool {
        didSet {
            preferences.saveShowHelperFiles(showHelperFiles)
        }
    }
    var automaticallyImportDetectedMedia: Bool {
        didSet {
            preferences.saveAutomaticallyImportDetectedMedia(automaticallyImportDetectedMedia)
            if automaticallyImportDetectedMedia {
                scheduleAutomaticImportForCurrentSource()
            } else {
                lastAutomaticImportAttemptKey = nil
            }
        }
    }
    var destinationURL: URL? {
        didSet {
            preferences.saveDestinationURL(destinationURL)
            refreshDestinationAvailability()
        }
    }
    var organizationMode: DestinationOrganizationMode {
        didSet {
            preferences.saveOrganizationMode(organizationMode)
            refreshDuplicateStates()
        }
    }

    init(
        preferences: UserPreferences = UserPreferences(),
        discoverVolumeSources: @escaping DiscoverVolumeSourcesAction = { VolumeDiscoveryService().discover() },
        discoverImageCaptureSources: @escaping DiscoverImageCaptureSourcesAction = { ImageCaptureDiscoveryService.shared.currentSources() },
        scanSource: @escaping ScanSourceAction = { source in
            guard let rootURL = source.rootURL else {
                return []
            }

            return (try? VolumeSourceScanner().scan(sourceID: source.id, rootURL: rootURL)) ?? []
        },
        groupAssets: @escaping GroupAssetsAction = { CaptureGrouper().group($0) },
        duplicateStateResolver: @escaping DuplicateStateResolver = { captures, destinationURL, organizationMode, cameraName in
            guard let index = try? DestinationFingerprintIndex.buildForImportDestinations(
                captures: captures,
                destinationRoot: destinationURL,
                organizationMode: organizationMode,
                cameraName: cameraName
            ) else {
                return [:]
            }

            var results: [String: CaptureDuplicateState] = [:]
            results.reserveCapacity(captures.count)
            for capture in captures {
                if Task.isCancelled { break }
                results[capture.id] = index.duplicateState(for: capture)
            }
            return results
        },
        importCapturesAction: @escaping ImportCapturesAction = { captures, destinationURL, organizationMode, cameraName, overwriteDuplicates, onProgress in
            try ImportCoordinator().importCaptures(
                captures,
                destinationRoot: destinationURL,
                organizationMode: organizationMode,
                cameraName: cameraName,
                overwriteDuplicates: overwriteDuplicates,
                onProgress: onProgress
            )
        },
        deleteCaptureFilesAction: @escaping DeleteCaptureFilesAction = { captures in
            SourceDeletionService().delete(captures)
        },
        deleteSourceFilesAction: @escaping DeleteSourceFilesAction = { files in
            SourceDeletionService().delete(files)
        },
        ejectSourceAction: @escaping EjectSourceAction = { source in
            try VolumeEjectionService().eject(source)
        },
        mediaProcessingTracker: MediaProcessingTracker = MediaProcessingTracker()
    ) {
        self.preferences = preferences
        self.discoverVolumeSources = discoverVolumeSources
        self.discoverImageCaptureSources = discoverImageCaptureSources
        self.scanSource = scanSource
        self.groupAssets = groupAssets
        self.duplicateStateResolver = duplicateStateResolver
        self.importCapturesAction = importCapturesAction
        self.deleteCaptureFilesAction = deleteCaptureFilesAction
        self.deleteSourceFilesAction = deleteSourceFilesAction
        self.ejectSourceAction = ejectSourceAction
        self.mediaProcessingTracker = mediaProcessingTracker
        self.destinationURL = preferences.destinationURL()
        self.organizationMode = preferences.organizationMode()
        self.showHelperFiles = preferences.showHelperFiles()
        self.automaticallyImportDetectedMedia = preferences.automaticallyImportDetectedMedia()
        refreshDestinationAvailability()
    }

    var selectedCaptures: [LogicalCapture] {
        return selectedCaptureIDs.compactMap { captureByID[$0] }
    }

    var duplicateCapturesInSelection: [LogicalCapture] {
        selectedCaptures.filter { duplicateState(for: $0) == .duplicate }
    }

    var partialDuplicateCapturesInSelection: [LogicalCapture] {
        selectedCaptures.filter { duplicateState(for: $0) == .partial }
    }

    var hasDuplicateCapturesInSelection: Bool {
        selectedDuplicateCaptureCount > 0
    }

    var visibleUnknownFolders: [UnknownFolder] {
        showUnknownFolders ? unknownFolders : []
    }

    var canImportSelection: Bool {
        destinationAvailability.isReachable && selectedCaptureCount > 0 && !isImporting
    }

    var canImportAllCaptures: Bool {
        destinationAvailability.isReachable && !captureIDs.isEmpty && !isImporting
    }

    var areAllCapturesSelected: Bool {
        !captureIDs.isEmpty && selectedCaptureCount == captureIDs.count
    }

    var canSelectAllCaptures: Bool {
        !isImporting && !captureIDs.isEmpty && !areAllCapturesSelected
    }

    var canDeselectAllCaptures: Bool {
        !isImporting && selectedCaptureCount > 0
    }

    var canClearSidecarFiles: Bool {
        selectedSource?.rootURL != nil && !sidecarFilesInSelectedSource.isEmpty && !isLoadingSource && !isImporting
    }

    func canEjectSource(_ source: SourceDevice) -> Bool {
        source.kind == .mountedVolume
            && source.rootURL != nil
            && ejectingSourceID == nil
            && !isLoadingSource
            && !isImporting
    }

    var importSummary: String? {
        guard let lastImportResult else {
            return nil
        }

        let importedCount = lastImportResult.captureResults.filter { $0.status == .imported }.count
        let skippedCount = lastImportResult.captureResults.filter { $0.status == .skippedDuplicate }.count
        let failedCount = lastImportResult.captureResults.filter { $0.status == .failed }.count

        var parts: [String] = []
        if importedCount > 0 {
            parts.append("\(importedCount) imported")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) failed")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func refreshSources(
        selectFirstIfNeeded: Bool = true,
        fallbackToFirstWhenSelectedUnavailable: Bool = true
    ) {
        scheduleSourceRefresh(
            selectFirstIfNeeded: selectFirstIfNeeded,
            fallbackToFirstWhenSelectedUnavailable: fallbackToFirstWhenSelectedUnavailable,
            preferNewDetectedMedia: false,
            previousSourceIDs: [],
            loadPreferredSourceAfterRefresh: false
        )
    }

    func refreshSourcesAndLoadPreferredSource(preferNewDetectedMedia: Bool = false) {
        let previousSourceIDs = Set(sources.map(\.id))

        scheduleSourceRefresh(
            selectFirstIfNeeded: false,
            fallbackToFirstWhenSelectedUnavailable: false,
            preferNewDetectedMedia: preferNewDetectedMedia,
            previousSourceIDs: previousSourceIDs,
            loadPreferredSourceAfterRefresh: true
        )
    }

    func loadSource(_ source: SourceDevice) {
        sourceLoadingTask?.cancel()
        sourceLoadingGeneration += 1
        duplicateDetectionTask?.cancel()
        duplicateDetectionGeneration += 1
        cancelActiveImport(resetProgress: true)
        lastAutomaticImportAttemptKey = nil
        let generation = sourceLoadingGeneration

        selectedSource = source
        isLoadingSource = true
        applyCaptureCacheSnapshot(CaptureCacheSnapshot(captures: [], duplicateStatesByCaptureID: [:]))
        unknownFolders = []
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        replaceSelectedCaptureIDs([])
        duplicateStatesByCaptureID = [:]
        duplicateStatesAreResolved = false

        let scanSource = scanSource
        let groupAssets = groupAssets

        sourceLoadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scannedFiles = scanSource(source)
            guard !Task.isCancelled else { return }

            let grouping = groupAssets(scannedFiles)
            guard !Task.isCancelled else { return }

            let snapshot = LoadedSourceSnapshot(grouping: grouping)
            guard !Task.isCancelled else { return }

            await self?.applyLoadedSource(snapshot, generation: generation)
        }
    }

    func awaitSourceLoading() async {
        await sourceRefreshTask?.value
        await sourceLoadingTask?.value
    }

    func awaitDuplicateDetection() async {
        await destinationAvailabilityTask?.value
        await sourceRefreshTask?.value
        await sourceLoadingTask?.value
        await destinationAvailabilityTask?.value
        await duplicateDetectionTask?.value
    }

    func awaitAutomaticImport() async {
        await automaticImportTask?.value
    }

    func awaitSourceEjection() async {
        await sourceEjectionTask?.value
    }

    func duplicateState(for capture: LogicalCapture) -> CaptureDuplicateState {
        duplicateStatesByCaptureID[capture.id] ?? .unique
    }

    func isCaptureSelected(_ capture: LogicalCapture) -> Bool {
        isCaptureSelected(id: capture.id)
    }

    func isCaptureSelected(id: String) -> Bool {
        selectedCaptureIDSet.contains(id)
    }

    func setCaptureSelected(_ capture: LogicalCapture, isSelected: Bool) {
        setCaptureSelected(id: capture.id, isSelected: isSelected)
    }

    func setCaptureSelected(id: String, isSelected: Bool) {
        guard captureByID[id] != nil else {
            return
        }

        if isSelected {
            appendSelectedCaptureID(id)
        } else {
            removeSelectedCaptureID(id)
        }
    }

    func selectAllCaptures() {
        replaceSelectedCaptureIDs(captureIDs)
    }

    func clearCaptureSelection() {
        replaceSelectedCaptureIDs([])
    }

    func toggleMarks(for ids: Set<String>) {
        guard !ids.isEmpty else { return }

        let allAlreadyMarked = ids.isSubset(of: selectedCaptureIDSet)

        if allAlreadyMarked {
            replaceSelectedCaptureIDs(selectedCaptureIDs.filter { !ids.contains($0) })
        } else {
            let missing = ids.subtracting(selectedCaptureIDSet)
            let additions = captureIDs.filter { missing.contains($0) }
            appendSelectedCaptureIDs(additions)
        }
    }

    func replaceSelectedCaptureIDs(_ ids: [String]) {
        var seenIDs = Set<String>()
        var filteredIDs: [String] = []
        filteredIDs.reserveCapacity(ids.count)

        for id in ids where captureByID[id] != nil && seenIDs.insert(id).inserted {
            filteredIDs.append(id)
        }

        applySelectedCaptureIDs(filteredIDs, idSet: seenIDs)
    }

    func dismissPendingDeletion() {
        pendingDeletionCaptureIDs.removeAll()
    }

    func refreshDestinationAvailability() {
        scheduleDestinationAvailabilityRefresh(refreshDependents: true)
    }

    @discardableResult
    func resolveDestinationAvailability(refreshDependents: Bool = true) async -> DestinationAvailability {
        scheduleDestinationAvailabilityRefresh(refreshDependents: refreshDependents)
        await destinationAvailabilityTask?.value
        return destinationAvailability
    }

    func awaitSourceRefresh() async {
        await sourceRefreshTask?.value
    }

    func awaitDestinationAvailability() async {
        await destinationAvailabilityTask?.value
    }

    func importSelectedCaptures(overwriteDuplicates: Bool) async {
        let capturesSnapshot = selectedCaptures
        await importCaptures(
            capturesSnapshot,
            from: selectedSource,
            overwriteDuplicates: overwriteDuplicates
        )
    }

    private func plannedImportByteCount(
        for captures: [LogicalCapture],
        overwriteDuplicates: Bool
    ) -> Int64 {
        captures.reduce(Int64(0)) { totalBytes, capture in
            if !overwriteDuplicates && duplicateState(for: capture) == .duplicate {
                return totalBytes
            }

            return totalBytes + capture.totalSize
        }
    }

    func deleteImportedCapturesFromSource() async {
        guard !pendingDeletionCaptureIDs.isEmpty else {
            return
        }

        let pendingIDs = Set(pendingDeletionCaptureIDs)
        let deletableCaptures = captures.filter { pendingIDs.contains($0.id) }
        let action = deleteCaptureFilesAction
        await action(deletableCaptures)
        pendingDeletionCaptureIDs = []

        if let selectedSource {
            loadSource(selectedSource)
        }
    }

    func canDeleteCaptureFromSource(id: String) -> Bool {
        guard let capture = captureByID[id] else {
            return false
        }

        return !isLoadingSource && !isImporting && !capture.memberFiles.isEmpty
    }

    func deleteCapturesFromSource(ids: Set<String>) async {
        guard !ids.isEmpty, !isLoadingSource, !isImporting else {
            return
        }

        let capturesToDelete = captures.filter { ids.contains($0.id) && !$0.memberFiles.isEmpty }
        guard !capturesToDelete.isEmpty else {
            return
        }

        let action = deleteCaptureFilesAction
        await action(capturesToDelete)
        pendingDeletionCaptureIDs.removeAll { ids.contains($0) }
        selectedCaptureIDs.removeAll { ids.contains($0) }

        if let selectedSource {
            loadSource(selectedSource)
        }
    }

    func clearSidecarFilesFromSelectedSource() async {
        guard selectedSource?.rootURL != nil else {
            return
        }

        let sidecarFiles = sidecarFilesInSelectedSource
        guard !sidecarFiles.isEmpty else {
            return
        }

        let action = deleteSourceFilesAction
        await action(sidecarFiles)

        if let selectedSource {
            loadSource(selectedSource)
        }
    }

    func ejectSource(_ source: SourceDevice) async {
        guard canEjectSource(source) else {
            return
        }

        sourceEjectionErrorMessage = nil
        ejectingSourceID = source.id

        let action = ejectSourceAction
        let wasSelectedSource = selectedSource?.id == source.id

        sourceEjectionTask = Task { [weak self] in
            do {
                try await action(source)
                self?.finishSourceEjection(
                    wasSelectedSource: wasSelectedSource,
                    errorMessage: nil
                )
            } catch {
                self?.finishSourceEjection(
                    wasSelectedSource: wasSelectedSource,
                    errorMessage: error.localizedDescription
                )
            }
        }

        await sourceEjectionTask?.value
    }

    func dismissSourceEjectionError() {
        sourceEjectionErrorMessage = nil
    }

    func addFolderSource(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let source = SourceDevice(
            id: "folder::\(standardizedURL.path(percentEncoded: false))",
            displayName: standardizedURL.lastPathComponent,
            kind: .folderBookmark,
            rootURL: standardizedURL,
            subtitle: standardizedURL.path(percentEncoded: false),
            state: .ready
        )

        if !folderSources.contains(source) {
            folderSources.append(source)
        }

        refreshSources()
        loadSource(source)
    }

    func capture(withID id: String) -> LogicalCapture? {
        captureByID[id]
    }

    private func scheduleSourceRefresh(
        selectFirstIfNeeded: Bool,
        fallbackToFirstWhenSelectedUnavailable: Bool,
        preferNewDetectedMedia: Bool,
        previousSourceIDs: Set<String>,
        loadPreferredSourceAfterRefresh: Bool
    ) {
        sourceRefreshTask?.cancel()
        sourceRefreshGeneration += 1
        let generation = sourceRefreshGeneration
        let folderSourcesSnapshot = folderSources
        let imageCaptureSources = discoverImageCaptureSources()
        let discoverVolumeSources = discoverVolumeSources

        sourceRefreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            let volumeSources = discoverVolumeSources()
            guard !Task.isCancelled else {
                return
            }

            await self?.applySourceRefresh(
                volumeSources: volumeSources,
                imageCaptureSources: imageCaptureSources,
                folderSources: folderSourcesSnapshot,
                generation: generation,
                selectFirstIfNeeded: selectFirstIfNeeded,
                fallbackToFirstWhenSelectedUnavailable: fallbackToFirstWhenSelectedUnavailable,
                preferNewDetectedMedia: preferNewDetectedMedia,
                previousSourceIDs: previousSourceIDs,
                loadPreferredSourceAfterRefresh: loadPreferredSourceAfterRefresh
            )
        }
    }

    private func applySourceRefresh(
        volumeSources: [SourceDevice],
        imageCaptureSources: [SourceDevice],
        folderSources: [SourceDevice],
        generation: Int,
        selectFirstIfNeeded: Bool,
        fallbackToFirstWhenSelectedUnavailable: Bool,
        preferNewDetectedMedia: Bool,
        previousSourceIDs: Set<String>,
        loadPreferredSourceAfterRefresh: Bool
    ) {
        guard generation == sourceRefreshGeneration else {
            return
        }

        let combined = mergeSources(
            volumeSources: volumeSources,
            imageCaptureSources: imageCaptureSources,
            folderSources: folderSources
        )
        let previousSelectedSource = selectedSource

        sources = combined

        if let previousSelectedSource {
            selectedSource = combined.first(where: { $0.id == previousSelectedSource.id })
                ?? combined.first(where: { normalizedName($0.displayName) == normalizedName(previousSelectedSource.displayName) })
                ?? (fallbackToFirstWhenSelectedUnavailable ? combined.first : nil)
        } else {
            selectedSource = selectFirstIfNeeded ? combined.first : nil
        }

        guard loadPreferredSourceAfterRefresh else {
            return
        }

        let newDetectedMedia = sources.first { source in
            preferNewDetectedMedia
                && automaticallyImportDetectedMedia
                && !previousSourceIDs.contains(source.id)
                && isAutomaticImportSource(source)
        }
        let sourceToLoad = newDetectedMedia ?? selectedSource

        if let sourceToLoad {
            loadSource(sourceToLoad)
        } else {
            clearLoadedSource()
        }
    }

    private func scheduleDestinationAvailabilityRefresh(refreshDependents: Bool) {
        destinationAvailabilityTask?.cancel()
        destinationAvailabilityGeneration += 1
        let generation = destinationAvailabilityGeneration

        guard let destinationURL else {
            destinationAvailabilityTask = nil
            applyDestinationAvailability(.notSelected, generation: generation, refreshDependents: refreshDependents)
            return
        }

        destinationAvailability = .checking
        if refreshDependents {
            refreshDestinationCapacity()
            refreshDuplicateStates()
        }

        let availabilityTask = Task.detached(priority: .utility) {
            DestinationAvailability.resolve(url: destinationURL)
        }

        destinationAvailabilityTask = Task { @MainActor [weak self] in
            let availability = await availabilityTask.value
            guard !Task.isCancelled else {
                return
            }

            self?.applyDestinationAvailability(
                availability,
                generation: generation,
                refreshDependents: refreshDependents
            )
        }
    }

    private func applyDestinationAvailability(
        _ availability: DestinationAvailability,
        generation: Int,
        refreshDependents: Bool
    ) {
        guard generation == destinationAvailabilityGeneration else {
            return
        }

        destinationAvailability = availability

        guard refreshDependents else {
            return
        }

        refreshDestinationCapacity()
        refreshDuplicateStates()
    }

    private func clearLoadedSource() {
        sourceLoadingTask?.cancel()
        sourceLoadingGeneration += 1
        duplicateDetectionTask?.cancel()
        duplicateDetectionGeneration += 1
        duplicateStatesAreResolved = false
        cancelActiveImport(resetProgress: true)

        selectedSource = nil
        isLoadingSource = false
        applyCaptureCacheSnapshot(CaptureCacheSnapshot(captures: [], duplicateStatesByCaptureID: [:]))
        unknownFolders = []
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        replaceSelectedCaptureIDs([])
        duplicateStatesByCaptureID = [:]
    }

    private func finishSourceEjection(
        wasSelectedSource: Bool,
        errorMessage: String?
    ) {
        ejectingSourceID = nil

        if let errorMessage {
            sourceEjectionErrorMessage = errorMessage
            return
        }

        if wasSelectedSource {
            refreshSourcesAndLoadPreferredSource()
        } else {
            refreshSources()
        }
    }

    private func applyLoadedSource(
        _ snapshot: LoadedSourceSnapshot,
        generation: Int
    ) {
        guard generation == sourceLoadingGeneration else {
            return
        }

        applyCaptureCacheSnapshot(snapshot.captureCache)
        unknownFolders = snapshot.unknownFolders
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        replaceSelectedCaptureIDs(snapshot.captureCache.captureIDs)
        isLoadingSource = false

        refreshDuplicateStates(preselectNonDuplicates: true)
    }

    private func refreshDuplicateStates(preselectNonDuplicates: Bool = false) {
        duplicateDetectionTask?.cancel()
        duplicateDetectionGeneration += 1
        duplicateStatesAreResolved = false
        if preselectNonDuplicates {
            pendingNonDuplicatePreselection = true
        }
        let generation = duplicateDetectionGeneration

        guard let destinationURL, destinationAvailability.isReachable else {
            duplicateStatesByCaptureID = [:]
            refreshCaptureRows(with: [:])
            rebuildSelectionTotals()
            if preselectNonDuplicates {
                replaceSelectedCaptureIDs(captureIDs)
            }
            return
        }

        let capturesSnapshot = captures
        let shouldPreselectNonDuplicates = preselectNonDuplicates || pendingNonDuplicatePreselection
        let resolver = duplicateStateResolver
        let organizationMode = organizationMode
        let cameraName = selectedSource?.displayName ?? "Imports"

        duplicateDetectionTask = Task.detached { [weak self] in
            let states = await resolver(capturesSnapshot, destinationURL, organizationMode, cameraName)
            if Task.isCancelled { return }
            let rows = capturesSnapshot.map { capture in
                CaptureRowPresentation(
                    capture: capture,
                    duplicateState: states[capture.id] ?? .unique
                )
            }
            await self?.applyDuplicateStates(
                states,
                rows: rows,
                for: capturesSnapshot,
                generation: generation,
                preselectNonDuplicates: shouldPreselectNonDuplicates
            )
        }
    }

    private func applyDuplicateStates(
        _ states: [String: CaptureDuplicateState],
        rows: [CaptureRowPresentation],
        for capturesSnapshot: [LogicalCapture],
        generation: Int,
        preselectNonDuplicates: Bool
    ) {
        guard generation == duplicateDetectionGeneration else {
            return
        }

        duplicateStatesByCaptureID = states
        duplicateStatesAreResolved = true
        captureRows = rows
        rebuildSelectionTotals()
        if preselectNonDuplicates {
            replaceSelectedCaptureIDs(capturesSnapshot
                .filter { (states[$0.id] ?? .unique) != .duplicate }
                .map(\.id))
            pendingNonDuplicatePreselection = false
        }
        scheduleAutomaticImportIfNeeded(
            capturesSnapshot: capturesSnapshot,
            states: states
        )
    }

    private func scheduleAutomaticImportForCurrentSource() {
        guard duplicateStatesAreResolved else {
            return
        }

        scheduleAutomaticImportIfNeeded(
            capturesSnapshot: captures,
            states: duplicateStatesByCaptureID
        )
    }

    private func scheduleAutomaticImportIfNeeded(
        capturesSnapshot: [LogicalCapture],
        states: [String: CaptureDuplicateState]
    ) {
        guard
            automaticallyImportDetectedMedia,
            automaticImportTask == nil,
            !isImporting,
            let source = selectedSource,
            source.kind == .mountedVolume,
            source.rootURL != nil,
            let destinationURL,
            destinationAvailability.isReachable
        else {
            return
        }

        let importableCaptures = capturesSnapshot.filter { capture in
            (states[capture.id] ?? .unique) == .unique
        }
        guard !importableCaptures.isEmpty else {
            return
        }

        let key = AutomaticImportAttemptKey(
            sourceID: source.id,
            destinationPath: destinationURL.standardizedFileURL.path(percentEncoded: false),
            organizationModeRawValue: organizationMode.rawValue,
            captureIDs: importableCaptures.map(\.id)
        )
        guard key != lastAutomaticImportAttemptKey else {
            return
        }

        lastAutomaticImportAttemptKey = key
        automaticImportTask = Task { [weak self] in
            await self?.importCaptures(
                importableCaptures,
                from: source,
                overwriteDuplicates: false
            )
            self?.automaticImportTask = nil
        }
    }

    private func importCaptures(
        _ capturesSnapshot: [LogicalCapture],
        from source: SourceDevice?,
        overwriteDuplicates: Bool
    ) async {
        let requestedImportGeneration = importGeneration
        let availability = await resolveDestinationAvailability(refreshDependents: false)

        guard
            requestedImportGeneration == importGeneration,
            let destinationURL,
            availability.isReachable,
            !capturesSnapshot.isEmpty,
            !isImporting
        else {
            return
        }

        let cameraName = source?.displayName ?? "Imports"
        let mode = organizationMode
        let action = importCapturesAction
        importGeneration += 1
        let generation = importGeneration

        activeImportGeneration = generation
        isImporting = true
        importProgress = ImportProgress(
            completedCaptures: 0,
            totalCaptures: capturesSnapshot.count,
            completedBytes: 0,
            totalBytes: plannedImportByteCount(
                for: capturesSnapshot,
                overwriteDuplicates: overwriteDuplicates
            ),
            currentCaptureName: capturesSnapshot.first?.displayName
        )

        let progressHandler: ImportProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in
                    guard
                        let self,
                        generation == self.importGeneration,
                        self.activeImportGeneration == generation,
                        self.isImporting
                    else {
                    return
                }

                self.importProgress = progress
            }
        }

        let worker = Task.detached(priority: .userInitiated) {
            do {
                return try action(
                    capturesSnapshot,
                    destinationURL,
                    mode,
                    cameraName,
                    overwriteDuplicates,
                    progressHandler
                )
            } catch {
                return ImportSessionResult(
                    captureResults: capturesSnapshot.map { capture in
                        CaptureImportResult(
                            captureID: capture.id,
                            status: .failed,
                            importedURLs: [],
                            isDeleteEligible: false
                        )
                    }
                )
            }
        }
        importWorkerTask = worker

        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard !Task.isCancelled else {
            clearImportStateIfActive(generation: generation)
            return
        }

        guard generation == importGeneration else {
            clearImportStateIfActive(generation: generation)
            return
        }

        importWorkerTask = nil
        activeImportGeneration = nil
        isImporting = false
        importProgress = nil
        lastImportResult = result
        pendingDeletionCaptureIDs = result.captureResults
            .filter(\.isDeleteEligible)
            .map(\.captureID)
        refreshDuplicateStates()
        refreshDestinationCapacity()
    }

    private func refreshDestinationCapacity() {
        destinationCapacityTask?.cancel()
        destinationCapacityGeneration += 1
        let generation = destinationCapacityGeneration

        guard let destinationURL, destinationAvailability.isReachable else {
            destinationCapacity = nil
            return
        }

        destinationCapacityTask = Task.detached(priority: .utility) { [weak self] in
            let capacity = DestinationCapacity.measure(at: destinationURL)
            guard !Task.isCancelled else { return }

            await self?.applyDestinationCapacity(capacity, generation: generation)
        }
    }

    private func applyDestinationCapacity(
        _ capacity: DestinationCapacity?,
        generation: Int
    ) {
        guard generation == destinationCapacityGeneration else {
            return
        }

        destinationCapacity = capacity
    }

    private func cancelActiveImport(resetProgress: Bool) {
        automaticImportTask?.cancel()
        automaticImportTask = nil
        importWorkerTask?.cancel()
        importWorkerTask = nil
        activeImportGeneration = nil
        importGeneration += 1

        if resetProgress {
            isImporting = false
            importProgress = nil
        }
    }

    private func clearImportStateIfActive(generation: Int) {
        guard activeImportGeneration == generation else {
            return
        }

        importWorkerTask = nil
        activeImportGeneration = nil
        isImporting = false
        importProgress = nil
    }

    private func applyCaptureCacheSnapshot(_ snapshot: CaptureCacheSnapshot) {
        isApplyingCaptureCacheSnapshot = true
        captures = snapshot.captures
        isApplyingCaptureCacheSnapshot = false
        captureIDs = snapshot.captureIDs
        captureByID = snapshot.captureByID
        captureSizeByID = snapshot.captureSizeByID
        sidecarFilesInSelectedSource = snapshot.sidecarFilesInSelectedSource
        captureRows = snapshot.captureRows
        replaceSelectedCaptureIDs(selectedCaptureIDs)
    }

    private func rebuildCaptureCaches() {
        let snapshot = CaptureCacheSnapshot(
            captures: captures,
            duplicateStatesByCaptureID: duplicateStatesByCaptureID
        )
        applyCaptureCacheSnapshot(snapshot)
    }

    private func appendSelectedCaptureIDs(_ ids: [String]) {
        guard !ids.isEmpty else {
            return
        }

        var updatedIDs = selectedCaptureIDs
        var updatedSet = selectedCaptureIDSet
        updatedIDs.reserveCapacity(selectedCaptureIDs.count + ids.count)

        for id in ids {
            guard captureByID[id] != nil, updatedSet.insert(id).inserted else {
                continue
            }

            updatedIDs.append(id)
        }

        applySelectedCaptureIDs(updatedIDs, idSet: updatedSet)
    }

    private func appendSelectedCaptureID(_ id: String) {
        guard captureByID[id] != nil, !selectedCaptureIDSet.contains(id) else {
            return
        }

        applySelectedCaptureIDs(
            selectedCaptureIDs + [id],
            idSet: selectedCaptureIDSet.union([id])
        )
    }

    private func removeSelectedCaptureID(_ id: String) {
        guard selectedCaptureIDSet.contains(id) else {
            return
        }

        var updatedSet = selectedCaptureIDSet
        updatedSet.remove(id)
        applySelectedCaptureIDs(
            selectedCaptureIDs.filter { $0 != id },
            idSet: updatedSet
        )
    }

    private func rebuildSelectionTotals() {
        applySelectionSummary(selectionSummary(for: selectedCaptureIDs))
    }

    private func applySelectedCaptureIDs(_ ids: [String], idSet: Set<String>) {
        if selectedCaptureIDs != ids {
            selectedCaptureIDs = ids
        }
        selectedCaptureIDSet = idSet
        applySelectionSummary(selectionSummary(for: ids))
    }

    private func selectionSummary(for ids: [String]) -> SelectionSummary {
        ids.reduce(into: SelectionSummary(count: 0, totalSize: 0, duplicateCount: 0, partialDuplicateCount: 0)) { summary, id in
            summary.count += 1
            summary.totalSize += captureSizeByID[id] ?? 0

            switch duplicateStateForCaptureID(id) {
            case .duplicate:
                summary.duplicateCount += 1
            case .partial:
                summary.partialDuplicateCount += 1
            case .unique:
                break
            }
        }
    }

    private func applySelectionSummary(_ summary: SelectionSummary) {
        if selectedCaptureCount != summary.count {
            selectedCaptureCount = summary.count
        }
        if selectedCapturesTotalSize != summary.totalSize {
            selectedCapturesTotalSize = summary.totalSize
        }
        if selectedDuplicateCaptureCount != summary.duplicateCount {
            selectedDuplicateCaptureCount = summary.duplicateCount
        }
        if selectedPartialDuplicateCaptureCount != summary.partialDuplicateCount {
            selectedPartialDuplicateCaptureCount = summary.partialDuplicateCount
        }
    }

    private func duplicateStateForCaptureID(_ id: String) -> CaptureDuplicateState {
        duplicateStatesByCaptureID[id] ?? .unique
    }

    private func refreshCaptureRows(with states: [String: CaptureDuplicateState]? = nil) {
        let states = states ?? duplicateStatesByCaptureID
        captureRows = captures.map { capture in
            let duplicateState = duplicateState(for: capture)
            return CaptureRowPresentation(
                capture: capture,
                duplicateState: states[capture.id] ?? duplicateState
            )
        }
    }

    private func mergeSources(
        volumeSources: [SourceDevice],
        imageCaptureSources: [SourceDevice],
        folderSources: [SourceDevice]
    ) -> [SourceDevice] {
        var mergedByName: [String: SourceDevice] = [:]
        for imageCaptureSource in imageCaptureSources {
            let name = normalizedName(imageCaptureSource.displayName)
            if mergedByName[name] == nil {
                mergedByName[name] = imageCaptureSource
            }
        }

        for volumeSource in volumeSources {
            mergedByName[normalizedName(volumeSource.displayName)] = volumeSource
        }

        let mergedHardwareSources = Array(mergedByName.values).sorted(by: sourceSortOrder)
        return (folderSources + mergedHardwareSources).sorted(by: sourceSortOrder)
    }

    private func sourceSortOrder(_ lhs: SourceDevice, _ rhs: SourceDevice) -> Bool {
        let lhsPriority = sourcePriority(lhs.kind)
        let rhsPriority = sourcePriority(rhs.kind)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func sourcePriority(_ kind: SourceDevice.Kind) -> Int {
        switch kind {
        case .mountedVolume:
            return 0
        case .folderBookmark:
            return 1
        case .imageCaptureDevice:
            return 2
        }
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isAutomaticImportSource(_ source: SourceDevice) -> Bool {
        source.kind == .mountedVolume && source.rootURL != nil
    }
}
