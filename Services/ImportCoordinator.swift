import Foundation

struct ImportPlan: Sendable {
    let captures: [PlannedCaptureImport]
    let totalBytes: Int64
}

struct PlannedCaptureImport: Sendable {
    let capture: LogicalCapture
    let duplicateState: CaptureDuplicateState
    let destinationDirectory: URL
    let files: [PlannedFileImport]
    let skipsDuplicate: Bool
    let duplicateFiles: [PlannedExistingFile]
}

struct PlannedFileImport: Sendable {
    enum Action: Equatable, Sendable {
        case copy
        case rename
        case replace
    }

    let source: SourceAssetFile
    let destinationURL: URL
    let action: Action
    let existingFile: PlannedExistingFile?
}

struct PlannedExistingFile: Sendable {
    let url: URL
    let size: Int64
    let modificationDate: Date?
}

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
        let plan = try planCaptures(
            captures,
            destinationRoot: destinationRoot,
            organizationMode: organizationMode,
            cameraName: cameraName,
            overwriteDuplicates: overwriteDuplicates
        )
        return importCaptures(plan, onProgress: onProgress)
    }

    func planCaptures(
        _ captures: [LogicalCapture],
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String,
        overwriteDuplicates: Bool
    ) throws -> ImportPlan {
        let index = try DestinationFingerprintIndex.buildForImportDestinations(
            captures: captures,
            destinationRoot: destinationRoot,
            organizationMode: organizationMode,
            cameraName: cameraName,
            fileManager: fileManager
        )
        var reservedPaths = Set<String>()
        var nextSuffixByPath: [String: Int] = [:]
        var plannedCaptures: [PlannedCaptureImport] = []
        plannedCaptures.reserveCapacity(captures.count)
        var totalBytes: Int64 = 0

        for capture in captures {
            try Task.checkCancellation()
            let duplicateState = index.duplicateState(for: capture)
            try Task.checkCancellation()
            let skipsDuplicate = duplicateState == .duplicate && !overwriteDuplicates
            let destinationDirectory = DestinationImportPlanner.destinationDirectory(
                for: capture,
                destinationRoot: destinationRoot,
                organizationMode: organizationMode,
                cameraName: cameraName
            )
            var files: [PlannedFileImport] = []
            var duplicateFiles: [PlannedExistingFile] = []

            if skipsDuplicate {
                duplicateFiles = try capture.memberFiles.map { file in
                    guard let matchedURL = index.match(for: file) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return try existingFile(at: matchedURL)
                }
            } else {
                files.reserveCapacity(capture.memberFiles.count)
                for file in capture.memberFiles {
                    try Task.checkCancellation()
                    let defaultURL = destinationDirectory.appendingPathComponent(file.fileName, isDirectory: false)
                    let defaultPath = defaultURL.standardizedFileURL.path(percentEncoded: false)
                    let exists = fileManager.fileExists(atPath: defaultPath)
                    let destinationURL: URL
                    let action: PlannedFileImport.Action

                    if reservedPaths.contains(defaultPath) {
                        destinationURL = uniqueURL(
                            for: defaultURL,
                            reservedPaths: reservedPaths,
                            nextSuffixByPath: &nextSuffixByPath
                        )
                        action = .rename
                    } else if overwriteDuplicates {
                        destinationURL = defaultURL
                        action = exists ? .replace : .copy
                    } else if exists {
                        destinationURL = uniqueURL(
                            for: defaultURL,
                            reservedPaths: reservedPaths,
                            nextSuffixByPath: &nextSuffixByPath
                        )
                        action = .rename
                    } else {
                        destinationURL = defaultURL
                        action = .copy
                    }

                    reservedPaths.insert(destinationURL.standardizedFileURL.path(percentEncoded: false))
                    let existingSnapshot = action == .replace ? try existingFile(at: destinationURL) : nil
                    files.append(PlannedFileImport(
                        source: file,
                        destinationURL: destinationURL,
                        action: action,
                        existingFile: existingSnapshot
                    ))
                }
                totalBytes += capture.totalSize
            }

            plannedCaptures.append(PlannedCaptureImport(
                capture: capture,
                duplicateState: duplicateState,
                destinationDirectory: destinationDirectory,
                files: files,
                skipsDuplicate: skipsDuplicate,
                duplicateFiles: duplicateFiles
            ))
        }

        return ImportPlan(captures: plannedCaptures, totalBytes: totalBytes)
    }

    func importCaptures(
        _ plan: ImportPlan,
        onProgress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) -> ImportSessionResult {
        var results: [CaptureImportResult] = []
        var progress = ImportProgressReporter(
            totalCaptures: plan.captures.count,
            totalBytes: plan.totalBytes,
            onProgress: onProgress
        )
        progress.start(firstCaptureName: plan.captures.first?.capture.displayName)

        for plannedCapture in plan.captures {
            let capture = plannedCapture.capture
            let expectedCopiedBytes: Int64 = plannedCapture.skipsDuplicate ? 0 : capture.totalSize
            progress.beginCapture(capture, expectedCopiedBytes: expectedCopiedBytes)

            if plannedCapture.skipsDuplicate {
                results.append(
                    CaptureImportResult(
                        captureID: capture.id,
                        status: plannedCapture.duplicateFiles.allSatisfy(isUnchanged) ? .skippedDuplicate : .failed,
                        importedURLs: [],
                        isDeleteEligible: false
                    )
                )
                progress.finishCapture()
                continue
            }

            do {
                let importedURLs = try importCapture(
                    plannedCapture,
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
        _ plannedCapture: PlannedCaptureImport,
        onCopiedBytes: (Int64) -> Void
    ) throws -> [URL] {
        try fileManager.createDirectory(at: plannedCapture.destinationDirectory, withIntermediateDirectories: true)

        var importedURLs: [URL] = []
        var rollbackActions: [ImportRollbackAction] = []

        do {
            for plannedFile in plannedCapture.files {
                let finalURL = plannedFile.destinationURL
                if let existingFile = plannedFile.existingFile, !isUnchanged(existingFile) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try importFile(
                    plannedFile.source,
                    to: finalURL,
                    overwriteExisting: plannedFile.action == .replace,
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
            try Task.checkCancellation()

            let copiedByteCount = try autoreleasepool {
                guard let data = try sourceHandle.read(upToCount: Self.copyChunkSize), !data.isEmpty else {
                    return 0
                }

                try destinationHandle.write(contentsOf: data)
                return data.count
            }

            guard copiedByteCount > 0 else {
                break
            }

            onCopiedBytes(Int64(copiedByteCount))
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

    private func uniqueURL(
        for destinationURL: URL,
        reservedPaths: Set<String>,
        nextSuffixByPath: inout [String: Int]
    ) -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        let stem = destinationURL.deletingPathExtension().lastPathComponent
        let fileExtension = destinationURL.pathExtension
        let basePath = destinationURL.standardizedFileURL.path(percentEncoded: false)

        var candidateIndex = nextSuffixByPath[basePath] ?? 2
        var candidateURL: URL

        while true {
            let fileName = if fileExtension.isEmpty {
                "\(stem) \(candidateIndex)"
            } else {
                "\(stem) \(candidateIndex).\(fileExtension)"
            }
            candidateURL = directory.appendingPathComponent(fileName, isDirectory: false)
            candidateIndex += 1
            let candidatePath = candidateURL.standardizedFileURL.path(percentEncoded: false)
            if !reservedPaths.contains(candidatePath) && !fileManager.fileExists(atPath: candidatePath) {
                nextSuffixByPath[basePath] = candidateIndex
                return candidateURL
            }
        }
    }

    private func existingFile(at url: URL) throws -> PlannedExistingFile {
        let attributes = try fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))
        guard let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return PlannedExistingFile(
            url: url,
            size: size.int64Value,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }

    private func isUnchanged(_ file: PlannedExistingFile) -> Bool {
        guard let current = try? existingFile(at: file.url) else {
            return false
        }
        return current.size == file.size && current.modificationDate == file.modificationDate
    }
}

private enum ImportRollbackAction {
    case remove(URL)
    case restore(backupURL: URL, destinationURL: URL)
}

private struct ImportProgressReporter {
    private static let minimumChunkProgressByteDelta: Int64 = 32 * 1024 * 1024

    let totalCaptures: Int
    let totalBytes: Int64
    let onProgress: @Sendable (ImportProgress) -> Void

    private var completedCaptures = 0
    private var completedBytes: Int64 = 0
    private var lastEmittedCompletedBytes: Int64?
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
        emit(force: true)
    }

    mutating func beginCapture(_ capture: LogicalCapture, expectedCopiedBytes: Int64) {
        currentCaptureStartBytes = completedBytes
        currentCaptureExpectedBytes = expectedCopiedBytes
        currentCaptureName = capture.displayName
        emit(force: true)
    }

    mutating func advanceCompletedBytes(by byteCount: Int64) {
        guard byteCount > 0 else {
            return
        }

        completedBytes = min(totalBytes, completedBytes + byteCount)
        emit(force: shouldEmitChunkProgress())
    }

    mutating func finishCapture() {
        completedCaptures = min(totalCaptures, completedCaptures + 1)
        completedBytes = min(totalBytes, max(completedBytes, currentCaptureStartBytes + currentCaptureExpectedBytes))
        emit(force: true)
    }

    mutating func finishAll() {
        completedCaptures = totalCaptures
        completedBytes = totalBytes
        currentCaptureName = nil
        emit(force: true)
    }

    private func shouldEmitChunkProgress() -> Bool {
        guard completedBytes > 0 else {
            return false
        }

        guard let lastEmittedCompletedBytes else {
            return true
        }

        if lastEmittedCompletedBytes == 0 {
            return true
        }

        return completedBytes - lastEmittedCompletedBytes >= Self.minimumChunkProgressByteDelta
    }

    private mutating func emit(force: Bool = false) {
        guard force || shouldEmitChunkProgress() else {
            return
        }

        lastEmittedCompletedBytes = completedBytes
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
        let datePathComponents = DestinationImportDatePathComponents(date: referenceDate)

        switch organizationMode {
        case .flat:
            return destinationRoot
        case .byDate:
            return destinationRoot
                .appendingPathComponent(datePathComponents.year, isDirectory: true)
                .appendingPathComponent(datePathComponents.day, isDirectory: true)
        case .byCameraAndDate:
            return destinationRoot
                .appendingPathComponent(cameraName, isDirectory: true)
                .appendingPathComponent(datePathComponents.year, isDirectory: true)
                .appendingPathComponent(datePathComponents.day, isDirectory: true)
        }
    }
}

private struct DestinationImportDatePathComponents {
    let year: String
    let day: String

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let yearValue = components.year ?? 0
        let monthValue = components.month ?? 1
        let dayValue = components.day ?? 1

        year = String(format: "%04d", yearValue)
        day = String(format: "%04d-%02d-%02d", yearValue, monthValue, dayValue)
    }
}
