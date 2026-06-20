import Foundation
import Testing

@testable import AutoImport

struct CaptureGroupingTests {
    @Test
    func groupsFilesWithSameFamilyIntoOneLogicalCapture() {
        let grouper = CaptureGrouper()
        let files = [
            makeAsset("DCIM/DJI_001/MOV_0001.MP4", classification: .video, duration: 14),
            makeAsset("DCIM/DJI_001/MOV_0001.LRF", classification: .sidecar),
            makeAsset("DCIM/DJI_001/MOV_0001.THM", classification: .sidecar),
        ]

        let result = grouper.group(files)

        #expect(result.captures.count == 1)
        #expect(result.captures[0].displayName == "MOV_0001")
        #expect(result.captures[0].primaryAsset?.relativePath == "DCIM/DJI_001/MOV_0001.MP4")
        #expect(result.captures[0].companionFiles.count == 2)
    }

    @Test
    func prefersHelperPreviewAssetsWithoutShowingThemByDefault() {
        let grouper = CaptureGrouper()
        let files = [
            makeAsset("DCIM/DJI_001/CLIP_0100.MP4", classification: .video, duration: 24),
            makeAsset("DCIM/DJI_001/CLIP_0100.LRV", classification: .sidecar, duration: 24),
            makeAsset("DCIM/DJI_001/CLIP_0100.THM", classification: .sidecar),
        ]

        let result = grouper.group(files)
        let capture = try! #require(result.captures.first)

        #expect(capture.preferredThumbnailAsset?.relativePath == "DCIM/DJI_001/CLIP_0100.THM")
        #expect(capture.preferredPreviewAsset?.relativePath == "DCIM/DJI_001/CLIP_0100.LRV")
        #expect(capture.preferredMetadataAsset?.relativePath == "DCIM/DJI_001/CLIP_0100.MP4")
        #expect(capture.visibleMemberFiles(showHelperFiles: false).map(\.relativePath) == [
            "DCIM/DJI_001/CLIP_0100.MP4",
        ])
        #expect(capture.visibleMemberFiles(showHelperFiles: true).map(\.relativePath) == [
            "DCIM/DJI_001/CLIP_0100.LRV",
            "DCIM/DJI_001/CLIP_0100.MP4",
            "DCIM/DJI_001/CLIP_0100.THM",
        ])
    }

    @Test
    func collapsesMultipartSegmentsIntoSingleCaptureAndSumsDuration() {
        let grouper = CaptureGrouper()
        let files = [
            makeAsset("PRIVATE/SONY/DJI_0002_001.MP4", classification: .video, duration: 12),
            makeAsset("PRIVATE/SONY/DJI_0002_002.MP4", classification: .video, duration: 18),
        ]

        let result = grouper.group(files)

        #expect(result.captures.count == 1)
        #expect(result.captures[0].displayName == "DJI_0002")
        #expect(result.captures[0].multipartSegments.count == 2)
        #expect(result.captures[0].totalDuration == 30)
    }

    @Test
    func bucketsUnknownFilesByParentFolder() {
        let grouper = CaptureGrouper()
        let files = [
            makeAsset("MISC/DEBUG/trace.bin", classification: .unknown),
            makeAsset("MISC/DEBUG/index.map", classification: .unknown),
        ]

        let result = grouper.group(files)

        #expect(result.captures.isEmpty)
        #expect(result.unknownFolders.count == 1)
        #expect(result.unknownFolders[0].relativeFolderPath == "MISC/DEBUG")
        #expect(result.unknownFolders[0].files.count == 2)
    }

    private func makeAsset(
        _ relativePath: String,
        classification: MediaClassification,
        duration: TimeInterval? = nil
    ) -> SourceAssetFile {
        SourceAssetFile(
            sourceID: "source",
            relativePath: relativePath,
            fileURL: URL(fileURLWithPath: "/tmp/\(relativePath)"),
            fileSize: 1_024,
            modificationDate: Date(timeIntervalSince1970: 100),
            classification: classification,
            duration: duration,
            pixelSize: nil
        )
    }
}
