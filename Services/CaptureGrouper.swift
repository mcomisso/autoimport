import Foundation

struct CaptureGrouper {
    func group(_ files: [SourceAssetFile]) -> CaptureGroupingResult {
        let sortedFiles = files.sorted {
            ($0.relativePath, $0.classification.rawValue) < ($1.relativePath, $1.classification.rawValue)
        }

        let unknownFolders = Dictionary(grouping: sortedFiles.filter { !$0.classification.isRecognizedCaptureMember }) { file in
            file.relativeDirectoryPath
        }
        .map { UnknownFolder(relativeFolderPath: $0.key, files: $0.value.sorted(by: byRelativePath)) }
        .sorted { $0.relativeFolderPath < $1.relativeFolderPath }

        let groupedRecognizedFiles = Dictionary(grouping: sortedFiles.filter(\.classification.isRecognizedCaptureMember), by: makeGroupingKey)

        let captures = groupedRecognizedFiles
            .map { key, group in
                makeCapture(groupingKey: key, files: group.sorted(by: byRelativePath))
            }
            .sorted {
                ($0.displayName, $0.primaryAsset?.relativePath ?? "") < ($1.displayName, $1.primaryAsset?.relativePath ?? "")
            }

        return CaptureGroupingResult(captures: captures, unknownFolders: unknownFolders)
    }

    private func makeGroupingKey(for file: SourceAssetFile) -> String {
        let stem = file.fileStem
        guard let familyStem = multipartFamilyStem(for: stem) else {
            return "\(file.relativeDirectoryPath)::\(stem)"
        }

        return "\(file.relativeDirectoryPath)::\(familyStem)"
    }

    private func makeCapture(groupingKey: String, files: [SourceAssetFile]) -> LogicalCapture {
        let displayName = groupingKey.components(separatedBy: "::").last ?? groupingKey
        let multipartSegments = files.filter { multipartFamilyStem(for: $0.fileStem) != nil && $0.classification.isPrimaryCandidate }
        let orderedMultipartSegments = multipartSegments.sorted(by: multipartOrder)

        let primaryAsset = orderedMultipartSegments.first
            ?? files.first(where: \.classification.isPrimaryCandidate)
            ?? files.first

        let companionFiles = files.filter { file in
            if orderedMultipartSegments.contains(file) {
                return false
            }

            guard let primaryAsset else {
                return false
            }

            return file.id != primaryAsset.id
        }

        let totalDuration = duration(for: orderedMultipartSegments.isEmpty ? (primaryAsset.map { [$0] } ?? []) : orderedMultipartSegments)

        return LogicalCapture(
            id: groupingKey,
            displayName: displayName,
            primaryAsset: primaryAsset,
            memberFiles: files,
            companionFiles: companionFiles,
            multipartSegments: orderedMultipartSegments,
            totalDuration: totalDuration
        )
    }

    private func duration(for files: [SourceAssetFile]) -> TimeInterval? {
        let durations = files.compactMap(\.duration)
        guard !durations.isEmpty else {
            return nil
        }

        return durations.reduce(0, +)
    }

    private func multipartFamilyStem(for stem: String) -> String? {
        guard let match = stem.wholeMatch(of: /^(.*?_\d{4})_(\d{3,4})$/) else {
            return nil
        }

        return String(match.1)
    }

    private func multipartOrder(_ lhs: SourceAssetFile, _ rhs: SourceAssetFile) -> Bool {
        multipartSequence(of: lhs.fileStem) < multipartSequence(of: rhs.fileStem)
    }

    private func multipartSequence(of stem: String) -> Int {
        guard let match = stem.wholeMatch(of: /^(.*?_\d{4})_(\d{3,4})$/) else {
            return 0
        }

        return Int(match.2) ?? 0
    }

    private func byRelativePath(_ lhs: SourceAssetFile, _ rhs: SourceAssetFile) -> Bool {
        lhs.relativePath < rhs.relativePath
    }
}
