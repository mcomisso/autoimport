import Testing
import Foundation

@testable import AutoImport

@Test func scaffoldLoads() {
    #expect(true)
}

@Test func captureRowPresentationProvidesDisplayAndSortValues() {
    let date = Date(timeIntervalSince1970: 1_000)
    let primaryAsset = SourceAssetFile(
        sourceID: "camera",
        relativePath: "DCIM/Clip_0100.MP4",
        fileURL: URL(fileURLWithPath: "/tmp/DCIM/Clip_0100.MP4"),
        fileSize: 2_048,
        modificationDate: date,
        classification: .video,
        duration: 12,
        pixelSize: nil
    )
    let capture = LogicalCapture(
        id: "clip",
        displayName: "Clip_0100",
        primaryAsset: primaryAsset,
        memberFiles: [primaryAsset],
        companionFiles: [],
        multipartSegments: [primaryAsset, primaryAsset],
        totalDuration: 24
    )

    let row = CaptureRowPresentation(
        capture: capture,
        duplicateState: .unique,
        kindText: "Video",
        timestampText: CaptureDisplayFormatter.timestamp(date) ?? "-",
        sizeText: CaptureDisplayFormatter.fileSize(capture.totalSize),
        statusText: "2 parts · 0:24",
        detailTexts: ["2 parts · 0:24"]
    )

    #expect(row.id == "clip")
    #expect(row.captureSortValue == "clip_0100")
    #expect(row.kindText == "Video")
    #expect(row.kindSortValue == "video")
    #expect(row.modificationDateSortValue == date)
    #expect(row.sizeSortValue == 2_048)
    #expect(row.statusText == "2 parts · 0:24")
    #expect(row.statusSortValue == "2 parts · 0:24")
}

@Test func captureRowPresentationStatusPrefersDuplicateState() {
    let capture = LogicalCapture(
        id: "duplicate",
        displayName: "Clip_0101",
        primaryAsset: nil,
        memberFiles: [],
        companionFiles: [],
        multipartSegments: [],
        totalDuration: nil
    )

    let row = CaptureRowPresentation(
        capture: capture,
        duplicateState: .duplicate,
        kindText: "Capture",
        timestampText: "-",
        sizeText: CaptureDisplayFormatter.fileSize(capture.totalSize),
        statusText: "Already imported",
        detailTexts: []
    )

    #expect(row.statusText == "Already imported")
    #expect(row.statusSortValue == "already imported")
    #expect(row.isDuplicate)
}
