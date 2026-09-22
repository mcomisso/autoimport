import Foundation
import Testing

@testable import AutoImport

struct CaptureSelectionTests {
    @Test
    func preservesOrderAndKeepsIncrementalTotalsInSync() {
        var selection = CaptureSelection()
        selection.updateCaptures([capture("a", size: 10), capture("b", size: 20), capture("c", size: 30)])
        selection.updateDuplicateStates(["b": .partial, "c": .duplicate])
        selection.replace(["b", "missing", "a", "b"])

        #expect(selection.ids == ["b", "a"])
        #expect(selection.summary == .init(count: 2, totalSize: 30, duplicateCount: 0, partialDuplicateCount: 1))

        selection.setSelected("c", isSelected: true)
        #expect(selection.summary == .init(count: 3, totalSize: 60, duplicateCount: 1, partialDuplicateCount: 1))

        selection.setSelected("b", isSelected: false)
        #expect(selection.ids == ["a", "c"])
        #expect(selection.summary == .init(count: 2, totalSize: 40, duplicateCount: 1, partialDuplicateCount: 0))
    }

    @Test
    func togglesMarksAsAGroupAndDropsRemovedCaptures() {
        var selection = CaptureSelection()
        selection.updateCaptures([capture("a", size: 10), capture("b", size: 20), capture("c", size: 30)])
        selection.replace(["a"])

        selection.toggleMarks(["a", "b", "missing"], inCaptureOrder: ["a", "b", "c"])
        #expect(selection.ids == ["a", "b"])

        selection.toggleMarks(["a", "b"], inCaptureOrder: ["a", "b", "c"])
        #expect(selection.ids.isEmpty)
        #expect(selection.summary == .init())

        selection.replace(["a", "c"])
        selection.updateCaptures([capture("b", size: 20), capture("c", size: 50)])
        #expect(selection.ids == ["c"])
        #expect(selection.summary.totalSize == 50)
    }

    private func capture(_ id: String, size: Int64) -> LogicalCapture {
        let file = SourceAssetFile(
            sourceID: "source",
            relativePath: "\(id).jpg",
            fileURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            fileSize: size,
            modificationDate: .distantPast,
            classification: .image,
            duration: nil,
            pixelSize: nil
        )
        return LogicalCapture(
            id: id,
            displayName: id,
            primaryAsset: file,
            memberFiles: [file],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
    }
}
