import Foundation
import Observation

struct CaptureRowPresentation: Identifiable, Hashable, Sendable {
    let capture: LogicalCapture
    let duplicateState: CaptureDuplicateState
    let kindText: String
    let timestampText: String
    let sizeText: String
    let statusText: String
    let detailTexts: [String]

    init(capture: LogicalCapture, duplicateState: CaptureDuplicateState) {
        self.init(
            capture: capture,
            duplicateState: duplicateState,
            kindText: Self.kindText(for: capture),
            timestampText: CaptureDisplayFormatter.timestamp(capture.primaryAsset?.modificationDate) ?? "-",
            sizeText: CaptureDisplayFormatter.fileSize(capture.totalSize),
            statusText: Self.statusText(for: capture, duplicateState: duplicateState),
            detailTexts: Self.detailTexts(for: capture)
        )
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
        self.capture = capture
        self.duplicateState = duplicateState
        self.kindText = kindText
        self.timestampText = timestampText
        self.sizeText = sizeText
        self.statusText = statusText
        self.detailTexts = detailTexts
    }

    var id: String {
        capture.id
    }

    var captureSortValue: String {
        normalizedSortValue(capture.displayName)
    }

    var kindSortValue: String {
        normalizedSortValue(kindText)
    }

    var modificationDateSortValue: Date {
        capture.primaryAsset?.modificationDate ?? .distantPast
    }

    var sizeSortValue: Int64 {
        capture.totalSize
    }

    var statusSortValue: String {
        normalizedSortValue(statusText)
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

    private func normalizedSortValue(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

@MainActor
@Observable
final class AppStore {
    typealias DiscoverSourcesAction = @MainActor () -> [SourceDevice]
    typealias ScanSourceAction = @Sendable (SourceDevice) -> [SourceAssetFile]
    typealias GroupAssetsAction = @Sendable ([SourceAssetFile]) -> CaptureGroupingResult
    typealias DuplicateStateResolver = @Sendable ([LogicalCapture], URL, DestinationOrganizationMode, String) async -> [String: CaptureDuplicateState]
    typealias ImportProgressHandler = @Sendable (ImportProgress) -> Void
    typealias ImportCapturesAction = @Sendable ([LogicalCapture], URL, DestinationOrganizationMode, String, Bool, @escaping ImportProgressHandler) async -> ImportSessionResult
    typealias DeleteCaptureFilesAction = @Sendable ([LogicalCapture]) async -> Void
    typealias DeleteSourceFilesAction = @Sendable ([SourceAssetFile]) async -> Void
    typealias EjectSourceAction = @Sendable (SourceDevice) async throws -> Void

    private let preferences: UserPreferences
    private let discoverVolumeSources: DiscoverSourcesAction
    private let discoverImageCaptureSources: DiscoverSourcesAction
    private let scanSource: ScanSourceAction
    private let groupAssets: GroupAssetsAction
    private let duplicateStateResolver: DuplicateStateResolver
    private let importCapturesAction: ImportCapturesAction
    private let deleteCaptureFilesAction: DeleteCaptureFilesAction
    private let deleteSourceFilesAction: DeleteSourceFilesAction
    private let ejectSourceAction: EjectSourceAction

    private var folderSources: [SourceDevice] = []
    private var duplicateStatesByCaptureID: [String: CaptureDuplicateState] = [:]
    private var sourceLoadingTask: Task<Void, Never>?
    private var sourceLoadingGeneration = 0
    private var duplicateDetectionTask: Task<Void, Never>?
    private var duplicateDetectionGeneration = 0
    private var destinationCapacityTask: Task<Void, Never>?
    private var destinationCapacityGeneration = 0
    private var sourceEjectionTask: Task<Void, Never>?

    @ObservationIgnored private var captureByID: [String: LogicalCapture] = [:]
    @ObservationIgnored private var captureSizeByID: [String: Int64] = [:]
    @ObservationIgnored private var selectedCaptureIDSet: Set<String> = []

    var sources: [SourceDevice] = []
    var selectedSource: SourceDevice?
    var captures: [LogicalCapture] = [] {
        didSet {
            rebuildCaptureCaches()
        }
    }
    private(set) var captureIDs: [String] = []
    private(set) var captureRows: [CaptureRowPresentation] = []
    var unknownFolders: [UnknownFolder] = []
    var selectedCaptureIDs: [String] = [] {
        didSet {
            rebuildSelectionCaches()
        }
    }
    private(set) var selectedCapturesTotalSize: Int64 = 0
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
    var destinationURL: URL? {
        didSet {
            preferences.saveDestinationURL(destinationURL)
            updateDestinationAvailability()
            refreshDestinationCapacity()
            refreshDuplicateStates()
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
        discoverVolumeSources: @escaping DiscoverSourcesAction = { VolumeDiscoveryService().discover() },
        discoverImageCaptureSources: @escaping DiscoverSourcesAction = { ImageCaptureDiscoveryService.shared.currentSources() },
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
            await Task.detached {
                (try? ImportCoordinator().importCaptures(
                    captures,
                    destinationRoot: destinationURL,
                    organizationMode: organizationMode,
                    cameraName: cameraName,
                    overwriteDuplicates: overwriteDuplicates,
                    onProgress: onProgress
                )) ?? ImportSessionResult(
                    captureResults: captures.map {
                        CaptureImportResult(
                            captureID: $0.id,
                            status: .failed,
                            importedURLs: [],
                            isDeleteEligible: false
                        )
                    }
                )
            }.value
        },
        deleteCaptureFilesAction: @escaping DeleteCaptureFilesAction = { captures in
            SourceDeletionService().delete(captures)
        },
        deleteSourceFilesAction: @escaping DeleteSourceFilesAction = { files in
            SourceDeletionService().delete(files)
        },
        ejectSourceAction: @escaping EjectSourceAction = { source in
            try VolumeEjectionService().eject(source)
        }
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
        self.destinationURL = preferences.destinationURL()
        self.organizationMode = preferences.organizationMode()
        self.showHelperFiles = preferences.showHelperFiles()
        updateDestinationAvailability()
        refreshDestinationCapacity()
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

    var visibleUnknownFolders: [UnknownFolder] {
        showUnknownFolders ? unknownFolders : []
    }

    var canImportSelection: Bool {
        destinationAvailability.isReachable && !selectedCaptures.isEmpty && !isImporting
    }

    var canImportAllCaptures: Bool {
        destinationAvailability.isReachable && !captures.isEmpty && !isImporting
    }

    var areAllCapturesSelected: Bool {
        guard !captureIDs.isEmpty else {
            return false
        }

        return Set(captureIDs).isSubset(of: selectedCaptureIDSet)
    }

    var canSelectAllCaptures: Bool {
        !isImporting && !captureIDs.isEmpty && !areAllCapturesSelected
    }

    var canDeselectAllCaptures: Bool {
        !isImporting && !selectedCaptureIDs.isEmpty
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

    func refreshSources() {
        let volumeSources = discoverVolumeSources()
        let imageCaptureSources = discoverImageCaptureSources()
        let combined = mergeSources(volumeSources: volumeSources, imageCaptureSources: imageCaptureSources, folderSources: folderSources)

        sources = combined

        guard let selectedSource else {
            self.selectedSource = combined.first
            return
        }

        self.selectedSource = combined.first(where: { $0.id == selectedSource.id })
            ?? combined.first(where: { normalizedName($0.displayName) == normalizedName(selectedSource.displayName) })
            ?? combined.first
    }

    func loadSource(_ source: SourceDevice) {
        sourceLoadingTask?.cancel()
        sourceLoadingGeneration += 1
        let generation = sourceLoadingGeneration

        selectedSource = source
        isLoadingSource = true
        captures = []
        unknownFolders = []
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        selectedCaptureIDs = []
        duplicateStatesByCaptureID = [:]
        refreshCaptureRows()

        let scanSource = scanSource
        let groupAssets = groupAssets

        sourceLoadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scannedFiles = scanSource(source)
            guard !Task.isCancelled else { return }

            let grouping = groupAssets(scannedFiles)
            guard !Task.isCancelled else { return }

            await self?.applyLoadedSource(grouping, generation: generation)
        }
    }

    func awaitSourceLoading() async {
        await sourceLoadingTask?.value
    }

    func awaitDuplicateDetection() async {
        await sourceLoadingTask?.value
        await duplicateDetectionTask?.value
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
        if isSelected {
            guard !selectedCaptureIDSet.contains(id) else {
                return
            }

            selectedCaptureIDs.append(id)
        } else {
            selectedCaptureIDs.removeAll { $0 == id }
        }
    }

    func selectAllCaptures() {
        selectedCaptureIDs = captures.map(\.id)
    }

    func clearCaptureSelection() {
        selectedCaptureIDs.removeAll()
    }

    func toggleMarks(for ids: Set<String>) {
        guard !ids.isEmpty else { return }

        let allAlreadyMarked = ids.isSubset(of: selectedCaptureIDSet)

        if allAlreadyMarked {
            selectedCaptureIDs.removeAll { ids.contains($0) }
        } else {
            let missing = ids.subtracting(selectedCaptureIDSet)
            let additions = captures.map(\.id).filter { missing.contains($0) }
            selectedCaptureIDs.append(contentsOf: additions)
        }
    }

    func dismissPendingDeletion() {
        pendingDeletionCaptureIDs.removeAll()
    }

    func refreshDestinationAvailability() {
        let previousAvailability = destinationAvailability
        updateDestinationAvailability()

        guard previousAvailability != destinationAvailability else {
            return
        }

        refreshDestinationCapacity()
        refreshDuplicateStates()
    }

    func importSelectedCaptures(overwriteDuplicates: Bool) async {
        refreshDestinationAvailability()

        let capturesSnapshot = selectedCaptures
        guard
            let destinationURL,
            destinationAvailability.isReachable,
            !capturesSnapshot.isEmpty,
            !isImporting
        else {
            return
        }

        let cameraName = selectedSource?.displayName ?? "Imports"
        let mode = organizationMode
        let action = importCapturesAction

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
        defer {
            isImporting = false
            importProgress = nil
        }

        let progressHandler: ImportProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.importProgress = progress
            }
        }

        let result = await action(
            capturesSnapshot,
            destinationURL,
            mode,
            cameraName,
            overwriteDuplicates,
            progressHandler
        )

        lastImportResult = result
        pendingDeletionCaptureIDs = result.captureResults
            .filter(\.isDeleteEligible)
            .map(\.captureID)
        refreshDuplicateStates()
        refreshDestinationCapacity()
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

    private func updateDestinationAvailability() {
        guard let destinationURL else {
            destinationAvailability = .notSelected
            return
        }

        destinationAvailability = .resolve(url: destinationURL)
    }

    private func clearLoadedSource() {
        sourceLoadingTask?.cancel()
        sourceLoadingGeneration += 1
        duplicateDetectionTask?.cancel()
        duplicateDetectionGeneration += 1

        selectedSource = nil
        isLoadingSource = false
        captures = []
        unknownFolders = []
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        selectedCaptureIDs = []
        duplicateStatesByCaptureID = [:]
        refreshCaptureRows()
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

        refreshSources()

        guard wasSelectedSource else {
            return
        }

        if let selectedSource {
            loadSource(selectedSource)
        } else {
            clearLoadedSource()
        }
    }

    private func applyLoadedSource(
        _ grouping: CaptureGroupingResult,
        generation: Int
    ) {
        guard generation == sourceLoadingGeneration else {
            return
        }

        captures = grouping.captures
        unknownFolders = grouping.unknownFolders
        pendingDeletionCaptureIDs = []
        lastImportResult = nil
        selectedCaptureIDs = captures.map(\.id)
        isLoadingSource = false

        refreshDuplicateStates(preselectNonDuplicates: true)
    }

    private func refreshDuplicateStates(preselectNonDuplicates: Bool = false) {
        duplicateDetectionTask?.cancel()
        duplicateDetectionGeneration += 1
        let generation = duplicateDetectionGeneration

        guard let destinationURL, destinationAvailability.isReachable else {
            duplicateStatesByCaptureID = [:]
            refreshCaptureRows()
            if preselectNonDuplicates {
                selectedCaptureIDs = captures.map(\.id)
            }
            return
        }

        let capturesSnapshot = captures
        let resolver = duplicateStateResolver
        let organizationMode = organizationMode
        let cameraName = selectedSource?.displayName ?? "Imports"

        duplicateDetectionTask = Task.detached { [weak self] in
            let states = await resolver(capturesSnapshot, destinationURL, organizationMode, cameraName)
            if Task.isCancelled { return }
            await self?.applyDuplicateStates(
                states,
                for: capturesSnapshot,
                generation: generation,
                preselectNonDuplicates: preselectNonDuplicates
            )
        }
    }

    private func applyDuplicateStates(
        _ states: [String: CaptureDuplicateState],
        for capturesSnapshot: [LogicalCapture],
        generation: Int,
        preselectNonDuplicates: Bool
    ) {
        guard generation == duplicateDetectionGeneration else {
            return
        }

        duplicateStatesByCaptureID = states
        refreshCaptureRows()
        if preselectNonDuplicates {
            selectedCaptureIDs = capturesSnapshot
                .filter { (states[$0.id] ?? .unique) != .duplicate }
                .map(\.id)
        }
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

    private func rebuildCaptureCaches() {
        captureIDs = captures.map(\.id)
        captureByID = Dictionary(captures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        captureSizeByID = Dictionary(captures.map { ($0.id, $0.totalSize) }, uniquingKeysWith: { first, _ in first })
        sidecarFilesInSelectedSource = captures
            .flatMap(\.memberFiles)
            .filter(\.isHelperFile)
            .sorted { $0.relativePath < $1.relativePath }
        rebuildSelectionCaches()
        refreshCaptureRows()
    }

    private func rebuildSelectionCaches() {
        selectedCaptureIDSet = Set(selectedCaptureIDs)
        selectedCapturesTotalSize = selectedCaptureIDs.reduce(Int64(0)) { total, captureID in
            total + (captureSizeByID[captureID] ?? 0)
        }
    }

    private func refreshCaptureRows() {
        captureRows = captures.map { capture in
            let duplicateState = duplicateState(for: capture)
            return CaptureRowPresentation(
                capture: capture,
                duplicateState: duplicateState
            )
        }
    }

    private func mergeSources(
        volumeSources: [SourceDevice],
        imageCaptureSources: [SourceDevice],
        folderSources: [SourceDevice]
    ) -> [SourceDevice] {
        var mergedByName = Dictionary(uniqueKeysWithValues: imageCaptureSources.map { (normalizedName($0.displayName), $0) })

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
}
