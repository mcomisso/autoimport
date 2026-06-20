import Foundation

struct DestinationFingerprintIndex: Sendable {
    private let filesByKey: [MetadataKey: [IndexedDestinationFile]]

    static func build(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> DestinationFingerprintIndex {
        try build(rootURLs: [rootURL], recursively: true, fileManager: fileManager)
    }

    static func buildForImportDestinations(
        captures: [LogicalCapture],
        destinationRoot: URL,
        organizationMode: DestinationOrganizationMode,
        cameraName: String,
        fileManager: FileManager = .default
    ) throws -> DestinationFingerprintIndex {
        try build(
            rootURLs: DestinationImportPlanner.destinationDirectories(
                for: captures,
                destinationRoot: destinationRoot,
                organizationMode: organizationMode,
                cameraName: cameraName
            ),
            recursively: false,
            fileManager: fileManager
        )
    }

    static func build(
        rootURLs: [URL],
        recursively: Bool,
        fileManager: FileManager = .default
    ) throws -> DestinationFingerprintIndex {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        var filesByKey: [MetadataKey: [IndexedDestinationFile]] = [:]

        for rootURL in uniqueURLs(rootURLs) {
            if recursively {
                try indexRecursiveFiles(
                    under: rootURL,
                    resourceKeys: resourceKeys,
                    fileManager: fileManager,
                    filesByKey: &filesByKey
                )
            } else {
                try indexImmediateFiles(
                    under: rootURL,
                    resourceKeys: resourceKeys,
                    fileManager: fileManager,
                    filesByKey: &filesByKey
                )
            }
        }

        return DestinationFingerprintIndex(filesByKey: filesByKey)
    }

    private static func indexRecursiveFiles(
        under rootURL: URL,
        resourceKeys: Set<URLResourceKey>,
        fileManager: FileManager,
        filesByKey: inout [MetadataKey: [IndexedDestinationFile]]
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            index(fileURL, resourceKeys: resourceKeys, filesByKey: &filesByKey)
        }
    }

    private static func indexImmediateFiles(
        under rootURL: URL,
        resourceKeys: Set<URLResourceKey>,
        fileManager: FileManager,
        filesByKey: inout [MetadataKey: [IndexedDestinationFile]]
    ) throws {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        for fileURL in fileURLs {
            try Task.checkCancellation()
            index(fileURL, resourceKeys: resourceKeys, filesByKey: &filesByKey)
        }
    }

    private static func index(
        _ fileURL: URL,
        resourceKeys: Set<URLResourceKey>,
        filesByKey: inout [MetadataKey: [IndexedDestinationFile]]
    ) {
        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true
        else {
            return
        }

        let size = Int64(values.fileSize ?? 0)
        let key = MetadataKey(name: fileURL.lastPathComponent.lowercased(), size: size)
        let file = IndexedDestinationFile(
            fileURL: fileURL,
            fileSize: size,
            modificationDate: values.contentModificationDate
        )
        filesByKey[key, default: []].append(file)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var unique: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path(percentEncoded: false)

            if seenPaths.insert(path).inserted {
                unique.append(url)
            }
        }

        return unique
    }

    func match(for sourceFile: SourceAssetFile) -> URL? {
        guard !Task.isCancelled else {
            return nil
        }

        let key = MetadataKey(
            name: sourceFile.fileName.lowercased(),
            size: sourceFile.fileSize
        )

        guard let candidates = filesByKey[key], !candidates.isEmpty else {
            return nil
        }

        let sourceDate = comparableDate(sourceFile.modificationDate)
        for candidate in candidates {
            guard !Task.isCancelled else {
                return nil
            }

            if let sourceDate, let candidateDate = candidate.modificationDate {
                guard Self.datesMatch(candidateDate, sourceDate) else {
                    continue
                }
            }

            return candidate.fileURL
        }

        return nil
    }

    func duplicateState(for capture: LogicalCapture) -> CaptureDuplicateState {
        guard !Task.isCancelled else {
            return .unique
        }

        var matchedFileCount = 0
        for file in capture.memberFiles {
            guard !Task.isCancelled else {
                return .unique
            }

            if match(for: file) != nil {
                matchedFileCount += 1
            }
        }

        switch matchedFileCount {
        case 0:
            return .unique
        case capture.memberFiles.count:
            return .duplicate
        default:
            return .partial
        }
    }

    private static func datesMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= 2
    }

    private func comparableDate(_ date: Date) -> Date? {
        date == .distantPast ? nil : date
    }
}

private struct MetadataKey: Hashable, Sendable {
    let name: String
    let size: Int64
}

private struct IndexedDestinationFile: Hashable, Sendable {
    let fileURL: URL
    let fileSize: Int64
    let modificationDate: Date?
}
