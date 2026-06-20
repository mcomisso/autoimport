import Foundation

struct VolumeSourceScanner {
    private let fileManager: FileManager
    private let directoryFilter: DirectoryFilter

    init(
        fileManager: FileManager = .default,
        directoryFilter: DirectoryFilter = DirectoryFilter()
    ) {
        self.fileManager = fileManager
        self.directoryFilter = directoryFilter
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

        for case let fileURL as URL in enumerator {
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

            files.append(
                SourceAssetFile(
                    sourceID: sourceID,
                    relativePath: relativePath(for: fileURL, under: rootURL),
                    fileURL: fileURL,
                    fileSize: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    classification: .classify(pathExtension: fileURL.pathExtension),
                    duration: nil,
                    pixelSize: nil
                )
            )
        }

        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private func relativePath(for fileURL: URL, under rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)

        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        return filePath
            .dropFirst(rootPath.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
