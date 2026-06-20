import Foundation

struct UnknownFolder: Identifiable, Hashable, Sendable {
    let relativeFolderPath: String
    let files: [SourceAssetFile]

    var id: String { relativeFolderPath }
}

struct LogicalCapture: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let primaryAsset: SourceAssetFile?
    let memberFiles: [SourceAssetFile]
    let companionFiles: [SourceAssetFile]
    let multipartSegments: [SourceAssetFile]
    let totalDuration: TimeInterval?

    var totalSize: Int64 {
        memberFiles.reduce(0) { $0 + $1.fileSize }
    }

    var preferredThumbnailAsset: SourceAssetFile? {
        memberFiles.first(where: \.isThumbnailHelper)
            ?? primaryAsset
            ?? preferredPreviewAsset
            ?? memberFiles.first(where: { $0.classification == .image })
            ?? memberFiles.first
    }

    var preferredPreviewAsset: SourceAssetFile? {
        memberFiles.first(where: \.isProxyVideoHelper)
            ?? primaryAsset
            ?? memberFiles.first(where: { $0.classification == .video || $0.classification == .image })
            ?? memberFiles.first
    }

    var preferredMetadataAsset: SourceAssetFile? {
        if let primaryAsset, primaryAsset.classification == .image || primaryAsset.classification == .video {
            return primaryAsset
        }

        return memberFiles.first { $0.classification == .image || $0.classification == .video }
    }

    func visibleMemberFiles(showHelperFiles: Bool) -> [SourceAssetFile] {
        guard !showHelperFiles else {
            return memberFiles
        }

        let nonHelperFiles = memberFiles.filter { !$0.isHelperFile }
        return nonHelperFiles.isEmpty ? memberFiles : nonHelperFiles
    }

    var helperFiles: [SourceAssetFile] {
        memberFiles.filter(\.isHelperFile)
    }
}

struct CaptureGroupingResult: Hashable, Sendable {
    let captures: [LogicalCapture]
    let unknownFolders: [UnknownFolder]
}
