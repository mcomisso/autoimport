import Foundation

struct CaptureGrouper {
    func group(_ files: [SourceAssetFile]) -> CaptureGroupingResult {
        var unknownFilesByFolder: [String: [SourceAssetFile]] = [:]
        var recognizedFilesByGroupingKey: [String: [SourceAssetFile]] = [:]

        for file in files {
            if file.classification.isRecognizedCaptureMember {
                recognizedFilesByGroupingKey[makeGroupingKey(for: file), default: []].append(file)
            } else {
                unknownFilesByFolder[file.relativeDirectoryPath, default: []].append(file)
            }
        }

        let unknownFolders = unknownFilesByFolder
            .map { UnknownFolder(relativeFolderPath: $0.key, files: $0.value.sorted(by: byRelativePath)) }
        .sorted { $0.relativeFolderPath < $1.relativeFolderPath }

        let captures = recognizedFilesByGroupingKey
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
        let multipartSegmentIDs = Set(orderedMultipartSegments.map(\.id))

        let primaryAsset = orderedMultipartSegments.first
            ?? files.first(where: \.classification.isPrimaryCandidate)
            ?? files.first

        let companionFiles = files.filter { file in
            if multipartSegmentIDs.contains(file.id) {
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
