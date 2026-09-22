import Foundation

struct VolumeSourceScanner {
    struct Configuration: Sendable {
        var maximumUnknownFileCount: Int

        init(maximumUnknownFileCount: Int = 512) {
            self.maximumUnknownFileCount = max(0, maximumUnknownFileCount)
        }
    }

    private let fileManager: FileManager
    private let directoryFilter: DirectoryFilter
    private let configuration: Configuration

    init(
        fileManager: FileManager = .default,
        directoryFilter: DirectoryFilter = DirectoryFilter(),
        configuration: Configuration = Configuration()
    ) {
        self.fileManager = fileManager
        self.directoryFilter = directoryFilter
        self.configuration = configuration
    }

    func scan(sourceID: String, rootURL: URL) throws -> [SourceAssetFile] {
        let typeKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
        ]
        let metadataKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let allKeys = typeKeys.union(metadataKeys)

        let rootType = try rootURL.resourceValues(forKeys: [.isDirectoryKey])
        guard rootType.isDirectory == true else {
            throw CocoaError(.fileReadUnknown)
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(typeKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var files: [SourceAssetFile] = []
        var unknownFileCount = 0
        let standardizedRootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let classification = MediaClassification.classify(pathExtension: fileURL.pathExtension)
            let values = try fileURL.resourceValues(
                forKeys: classification.isRecognizedCaptureMember ? allKeys : typeKeys
            )

            if values.isDirectory == true {
                if directoryFilter.shouldSkipDirectory(named: fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            if !classification.isRecognizedCaptureMember {
                guard unknownFileCount < configuration.maximumUnknownFileCount else {
                    continue
                }
                unknownFileCount += 1
            }

            let metadata = classification.isRecognizedCaptureMember
                ? values
                : try fileURL.resourceValues(forKeys: metadataKeys)

            files.append(
                SourceAssetFile(
                    sourceID: sourceID,
                    relativePath: relativePath(for: fileURL, underStandardizedRootPath: standardizedRootPath),
                    fileURL: fileURL,
                    fileSize: Int64(metadata.fileSize ?? 0),
                    modificationDate: metadata.contentModificationDate ?? .distantPast,
                    classification: classification,
                    duration: nil,
                    pixelSize: nil
                )
            )
        }

        if let enumerationError {
            throw enumerationError
        }

        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private func relativePath(for fileURL: URL, underStandardizedRootPath rootPath: String) -> String {
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        return filePath
            .dropFirst(rootPath.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
