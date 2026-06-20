import Foundation

struct ImportCoordinator {
    private static let copyChunkSize = 4 * 1024 * 1024

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importCaptures(
        _ captures: [LogicalCapture],
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String,
        overwriteDuplicates: Bool,
        onProgress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> ImportSessionResult {
        var results: [CaptureImportResult] = []
        let duplicateIndex = try DestinationFingerprintIndex.buildForImportDestinations(
            captures: captures,
            destinationRoot: destinationRoot,
            organizationMode: organizationMode,
            cameraName: cameraName,
            fileManager: fileManager
        )

        var progress = ImportProgressReporter(
            totalCaptures: captures.count,
            totalBytes: captures.reduce(Int64(0)) { totalBytes, capture in
                if duplicateIndex.duplicateState(for: capture) == .duplicate && !overwriteDuplicates {
                    return totalBytes
                }

                return totalBytes + capture.totalSize
            },
            onProgress: onProgress
        )
        progress.start(firstCaptureName: captures.first?.displayName)

        for capture in captures {
            let duplicateState = duplicateIndex.duplicateState(for: capture)
            let expectedCopiedBytes: Int64 = duplicateState == .duplicate && !overwriteDuplicates ? 0 : capture.totalSize
            progress.beginCapture(capture, expectedCopiedBytes: expectedCopiedBytes)

            if duplicateState == .duplicate && !overwriteDuplicates {
                results.append(
                    CaptureImportResult(
                        captureID: capture.id,
                        status: .skippedDuplicate,
                        importedURLs: [],
                        isDeleteEligible: false
                    )
                )
                progress.finishCapture()
                continue
            }

            do {
                let importedURLs = try importCapture(
                    capture,
                    destinationRoot: destinationRoot,
                    organizationMode: organizationMode,
                    cameraName: cameraName,
                    overwriteDuplicates: overwriteDuplicates,
                    onCopiedBytes: { byteCount in
                        progress.advanceCompletedBytes(by: byteCount)
                    }
                )

                results.append(
                    CaptureImportResult(
                        captureID: capture.id,
                        status: .imported,
                        importedURLs: importedURLs,
                        isDeleteEligible: true
                    )
                )
            } catch {
                results.append(
                    CaptureImportResult(
                        captureID: capture.id,
                        status: .failed,
                        importedURLs: [],
                        isDeleteEligible: false
                    )
                )
            }

            progress.finishCapture()
        }

        progress.finishAll()

        return ImportSessionResult(captureResults: results)
    }

    private func importCapture(
        _ capture: LogicalCapture,
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String,
        overwriteDuplicates: Bool,
        onCopiedBytes: (Int64) -> Void
    ) throws -> [URL] {
        let destinationDirectory = DestinationImportPlanner.destinationDirectory(
            for: capture,
            destinationRoot: destinationRoot,
            organizationMode: organizationMode,
            cameraName: cameraName
        )
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let defaultDestinationURLs = capture.memberFiles.reduce(into: [String: URL]()) { partialResult, file in
            partialResult[file.id] = destinationDirectory.appendingPathComponent(file.fileName, isDirectory: false)
        }

        let finalDestinationURLs = capture.memberFiles.reduce(into: [String: URL]()) { partialResult, file in
            let defaultURL = defaultDestinationURLs[file.id] ?? destinationDirectory.appendingPathComponent(file.fileName, isDirectory: false)

            if overwriteDuplicates {
                partialResult[file.id] = defaultURL
            } else if fileManager.fileExists(atPath: defaultURL.path(percentEncoded: false)) {
                partialResult[file.id] = uniqueURL(for: defaultURL)
            } else {
                partialResult[file.id] = defaultURL
            }
        }

        var importedURLs: [URL] = []
        var rollbackActions: [ImportRollbackAction] = []

        do {
            for file in capture.memberFiles {
                let finalURL = finalDestinationURLs[file.id] ?? destinationDirectory.appendingPathComponent(file.fileName, isDirectory: false)

                try importFile(
                    file,
                    to: finalURL,
                    overwriteExisting: overwriteDuplicates,
                    rollbackActions: &rollbackActions,
                    onCopiedBytes: onCopiedBytes
                )
                importedURLs.append(finalURL)
            }

            cleanupCommittedBackups(rollbackActions)
            return importedURLs
        } catch {
            rollback(rollbackActions)
            throw error
        }
    }

    private func importFile(
        _ file: SourceAssetFile,
        to finalURL: URL,
        overwriteExisting: Bool,
        rollbackActions: inout [ImportRollbackAction],
        onCopiedBytes: (Int64) -> Void
    ) throws {
        guard fileManager.fileExists(atPath: file.fileURL.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if fileManager.fileExists(atPath: finalURL.path(percentEncoded: false)) {
            guard overwriteExisting else {
                throw CocoaError(.fileWriteFileExists)
            }

            try replaceExistingFile(
                file,
                at: finalURL,
                rollbackActions: &rollbackActions,
                onCopiedBytes: onCopiedBytes
            )
        } else {
            try movePreparedCopy(file, to: finalURL, onCopiedBytes: onCopiedBytes)
            rollbackActions.append(.remove(finalURL))
        }
    }

    private func replaceExistingFile(
        _ file: SourceAssetFile,
        at finalURL: URL,
        rollbackActions: inout [ImportRollbackAction],
        onCopiedBytes: (Int64) -> Void
    ) throws {
        let temporaryURL = temporarySiblingURL(for: finalURL, prefix: "copy")
        let backupURL = temporarySiblingURL(for: finalURL, prefix: "backup")
        var originalMovedToBackup = false

        do {
            try copyPreparedFile(file, to: temporaryURL, onCopiedBytes: onCopiedBytes)
            try fileManager.moveItem(at: finalURL, to: backupURL)
            originalMovedToBackup = true
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            rollbackActions.append(.restore(backupURL: backupURL, destinationURL: finalURL))
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if originalMovedToBackup {
                restoreBackup(backupURL, to: finalURL)
            }
            throw error
        }
    }

    private func movePreparedCopy(
        _ file: SourceAssetFile,
        to finalURL: URL,
        onCopiedBytes: (Int64) -> Void
    ) throws {
        let temporaryURL = temporarySiblingURL(for: finalURL, prefix: "copy")

        do {
            try copyPreparedFile(file, to: temporaryURL, onCopiedBytes: onCopiedBytes)
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func copyPreparedFile(
        _ file: SourceAssetFile,
        to temporaryURL: URL,
        onCopiedBytes: (Int64) -> Void
    ) throws {
        do {
            try copyFileContents(from: file.fileURL, to: temporaryURL, onCopiedBytes: onCopiedBytes)
            try fileManager.setAttributes([.modificationDate: file.modificationDate], ofItemAtPath: temporaryURL.path(percentEncoded: false))
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func copyFileContents(
        from sourceURL: URL,
        to temporaryURL: URL,
        onCopiedBytes: (Int64) -> Void
    ) throws {
        let temporaryPath = temporaryURL.path(percentEncoded: false)
        guard fileManager.createFile(atPath: temporaryPath, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        while true {
            guard let data = try sourceHandle.read(upToCount: Self.copyChunkSize), !data.isEmpty else {
                break
            }

            try destinationHandle.write(contentsOf: data)
            onCopiedBytes(Int64(data.count))
        }
    }

    private func rollback(_ actions: [ImportRollbackAction]) {
        for action in actions.reversed() {
            switch action {
            case .remove(let url):
                try? fileManager.removeItem(at: url)
            case .restore(let backupURL, let destinationURL):
                restoreBackup(backupURL, to: destinationURL)
            }
        }
    }

    private func restoreBackup(_ backupURL: URL, to destinationURL: URL) {
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: destinationURL)
        }

        if fileManager.fileExists(atPath: backupURL.path(percentEncoded: false)) {
            try? fileManager.moveItem(at: backupURL, to: destinationURL)
        }
    }

    private func cleanupCommittedBackups(_ actions: [ImportRollbackAction]) {
        for action in actions {
            if case .restore(let backupURL, _) = action {
                try? fileManager.removeItem(at: backupURL)
            }
        }
    }

    private func temporarySiblingURL(for destinationURL: URL, prefix: String) -> URL {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let destinationName = destinationURL.lastPathComponent
        var candidateURL: URL

        repeat {
            candidateURL = directoryURL.appendingPathComponent(".autoimport-\(prefix)-\(UUID().uuidString)-\(destinationName)", isDirectory: false)
        } while fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false))

        return candidateURL
    }

    private func uniqueURL(for destinationURL: URL) -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        let stem = destinationURL.deletingPathExtension().lastPathComponent
        let fileExtension = destinationURL.pathExtension

        var candidateIndex = 2
        var candidateURL = destinationURL

        while fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
            let fileName = if fileExtension.isEmpty {
                "\(stem) \(candidateIndex)"
            } else {
                "\(stem) \(candidateIndex).\(fileExtension)"
            }
            candidateURL = directory.appendingPathComponent(fileName, isDirectory: false)
            candidateIndex += 1
        }

        return candidateURL
    }
}

private enum ImportRollbackAction {
    case remove(URL)
    case restore(backupURL: URL, destinationURL: URL)
}

private struct ImportProgressReporter {
    let totalCaptures: Int
    let totalBytes: Int64
    let onProgress: @Sendable (ImportProgress) -> Void

    private var completedCaptures = 0
    private var completedBytes: Int64 = 0
    private var currentCaptureStartBytes: Int64 = 0
    private var currentCaptureExpectedBytes: Int64 = 0
    private var currentCaptureName: String?

    init(
        totalCaptures: Int,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (ImportProgress) -> Void
    ) {
        self.totalCaptures = totalCaptures
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    mutating func start(firstCaptureName: String?) {
        currentCaptureName = firstCaptureName
        emit()
    }

    mutating func beginCapture(_ capture: LogicalCapture, expectedCopiedBytes: Int64) {
        currentCaptureStartBytes = completedBytes
        currentCaptureExpectedBytes = expectedCopiedBytes
        currentCaptureName = capture.displayName
        emit()
    }

    mutating func advanceCompletedBytes(by byteCount: Int64) {
        guard byteCount > 0 else {
            return
        }

        completedBytes = min(totalBytes, completedBytes + byteCount)
        emit()
    }

    mutating func finishCapture() {
        completedCaptures = min(totalCaptures, completedCaptures + 1)
        completedBytes = min(totalBytes, max(completedBytes, currentCaptureStartBytes + currentCaptureExpectedBytes))
        emit()
    }

    mutating func finishAll() {
        completedCaptures = totalCaptures
        completedBytes = totalBytes
        currentCaptureName = nil
        emit()
    }

    private func emit() {
        onProgress(ImportProgress(
            completedCaptures: completedCaptures,
            totalCaptures: totalCaptures,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentCaptureName: currentCaptureName
        ))
    }
}

enum DestinationImportPlanner {
    static func destinationDirectories(
        for captures: [LogicalCapture],
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String
    ) -> [URL] {
        var seenPaths = Set<String>()
        var directories: [URL] = []

        for capture in captures {
            let directory = destinationDirectory(
                for: capture,
                destinationRoot: destinationRoot,
                organizationMode: organizationMode,
                cameraName: cameraName
            )
            let path = directory.standardizedFileURL.path(percentEncoded: false)

            if seenPaths.insert(path).inserted {
                directories.append(directory)
            }
        }

        return directories
    }

    static func destinationDirectory(
        for capture: LogicalCapture,
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String
    ) -> URL {
        guard organizationMode != .flat else {
            return destinationRoot
        }

        let referenceDate = capture.primaryAsset?.modificationDate ?? .now
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        switch organizationMode {
        case .flat:
            return destinationRoot
        case .byDate:
            return destinationRoot
                .appendingPathComponent(yearFormatter.string(from: referenceDate), isDirectory: true)
                .appendingPathComponent(dayFormatter.string(from: referenceDate), isDirectory: true)
        case .byCameraAndDate:
            return destinationRoot
                .appendingPathComponent(cameraName, isDirectory: true)
                .appendingPathComponent(yearFormatter.string(from: referenceDate), isDirectory: true)
                .appendingPathComponent(dayFormatter.string(from: referenceDate), isDirectory: true)
        }
    }
}
