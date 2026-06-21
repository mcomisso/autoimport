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
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [SourceAssetFile] = []
        var unknownFileCount = 0
        let standardizedRootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: resourceKeys)

            if values.isDirectory == true {
                if directoryFilter.shouldSkipDirectory(named: fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            let classification = MediaClassification.classify(pathExtension: fileURL.pathExtension)
            if !classification.isRecognizedCaptureMember {
                unknownFileCount += 1
                guard unknownFileCount <= configuration.maximumUnknownFileCount else {
                    continue
                }
            }

            files.append(
                SourceAssetFile(
                    sourceID: sourceID,
                    relativePath: relativePath(for: fileURL, underStandardizedRootPath: standardizedRootPath),
                    fileURL: fileURL,
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    classification: classification,
                    duration: nil,
                    pixelSize: nil
                )
            )
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
