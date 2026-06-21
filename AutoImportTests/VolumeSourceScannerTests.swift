import Foundation
import Testing

@testable import AutoImport

struct VolumeSourceScannerTests {
    @Test
    func scansRecursivelyAndIgnoresKnownSystemDirectories() throws {
        let rootURL = try makeFixtureTree()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let scanner = VolumeSourceScanner()

        let files = try scanner.scan(sourceID: "camera", rootURL: rootURL)

        #expect(files.count == 3)
        #expect(files.map(\.relativePath).sorted() == [
            "DCIM/100MEDIA/CLIP_0001.MP4",
            "MISC/DEBUG.BIN",
            "PRIVATE/SONY/PHOTO_0001.JPG",
        ])
        #expect(files.first(where: { $0.relativePath == "DCIM/100MEDIA/CLIP_0001.MP4" })?.classification == .video)
        #expect(files.first(where: { $0.relativePath == "PRIVATE/SONY/PHOTO_0001.JPG" })?.classification == .image)
        #expect(files.first(where: { $0.relativePath == "MISC/DEBUG.BIN" })?.classification == .unknown)
    }

    @Test
    func samplesUnknownFilesWithoutDroppingRecognizedMedia() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeFile(named: "DCIM/100MEDIA/CLIP_0001.MP4", under: rootURL)
        try writeFile(named: "MISC/one.tmp", under: rootURL)
        try writeFile(named: "MISC/two.tmp", under: rootURL)
        try writeFile(named: "MISC/three.tmp", under: rootURL)

        let scanner = VolumeSourceScanner(
            configuration: VolumeSourceScanner.Configuration(maximumUnknownFileCount: 1)
        )

        let files = try scanner.scan(sourceID: "camera", rootURL: rootURL)

        #expect(files.map(\.relativePath) == [
            "DCIM/100MEDIA/CLIP_0001.MP4",
            "MISC/one.tmp",
        ])
        #expect(files.filter { !$0.classification.isRecognizedCaptureMember }.count == 1)
    }

    @Test
    func sourceDeletionServiceDeletesOnlyProvidedSidecarFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let videoURL = try writeFile(named: "DCIM/100MEDIA/CLIP_0002.MP4", under: rootURL)
        let thumbnailURL = try writeFile(named: "DCIM/100MEDIA/CLIP_0002.THM", under: rootURL)
        let subtitleURL = try writeFile(named: "DCIM/100MEDIA/CLIP_0002.SRT", under: rootURL)
        let unknownURL = try writeFile(named: "DCIM/100MEDIA/NOTES.BIN", under: rootURL)

        let files = try VolumeSourceScanner().scan(sourceID: "camera", rootURL: rootURL)
        let sidecarFiles = files.filter(\.isHelperFile)

        let results = SourceDeletionService(fileManager: RemovingOnlyFileManager()).delete(sidecarFiles)
        let allResultsDeleted = results.allSatisfy { $0.wasDeleted }

        #expect(results.count == sidecarFiles.count)
        #expect(allResultsDeleted)
        #expect(FileManager.default.fileExists(atPath: videoURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: subtitleURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: unknownURL.path(percentEncoded: false)))
    }

    @Test
    func sourceDeletionServiceReturnsPerFileAndCaptureResults() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let deletedURL = try writeFile(named: "DCIM/100MEDIA/DELETE.MP4", under: rootURL)
        let failingURL = try writeFile(named: "DCIM/100MEDIA/FAIL.MP4", under: rootURL)
        let missingURL = rootURL.appending(path: "DCIM/100MEDIA/MISSING.MP4")
        let deletedFile = makeAsset(deletedURL)
        let missingFile = makeAsset(missingURL)
        let failingFile = makeAsset(failingURL)
        let fileManager = FailingDeletionFileManager(failingURL: failingURL)

        let fileResults = SourceDeletionService(fileManager: fileManager).delete([
            deletedFile,
            missingFile,
            failingFile,
        ])

        #expect(fileResults[0].status == .deleted)
        #expect(fileResults[1].status == .missing)
        if case .failed(let message) = fileResults[2].status {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected failed deletion result")
        }
        #expect(!FileManager.default.fileExists(atPath: deletedURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: failingURL.path(percentEncoded: false)))

        let captureURL = try writeFile(named: "DCIM/100MEDIA/CAPTURE.MP4", under: rootURL)
        let captureFile = makeAsset(captureURL)
        let capture = LogicalCapture(
            id: "capture",
            displayName: "CAPTURE",
            primaryAsset: captureFile,
            memberFiles: [captureFile],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
        let captureResults = SourceDeletionService(fileManager: RemovingOnlyFileManager()).delete([capture])

        #expect(captureResults[0].captureID == "capture")
        #expect(captureResults[0].fileResults[0].status == .deleted)
        #expect(captureResults[0].failedFileResults.isEmpty)
    }

    private func makeFixtureTree() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try writeFile(named: "DCIM/100MEDIA/CLIP_0001.MP4", under: rootURL)
        try writeFile(named: "PRIVATE/SONY/PHOTO_0001.JPG", under: rootURL)
        try writeFile(named: "MISC/DEBUG.BIN", under: rootURL)
        try writeFile(named: ".Trashes/IGNORED.MP4", under: rootURL)
        try writeFile(named: ".Spotlight-V100/INDEX.DB", under: rootURL)

        return rootURL
    }

    @discardableResult
    private func writeFile(named relativePath: String, under rootURL: URL) throws -> URL {
        let fileURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: fileURL)
        return fileURL
    }

    private func makeAsset(_ fileURL: URL) -> SourceAssetFile {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SourceAssetFile(
            sourceID: "camera",
            relativePath: fileURL.lastPathComponent,
            fileURL: fileURL,
            fileSize: Int64(values?.fileSize ?? 0),
            modificationDate: values?.contentModificationDate ?? .distantPast,
            classification: .classify(pathExtension: fileURL.pathExtension),
            duration: nil,
            pixelSize: nil
        )
    }
}

private class RemovingOnlyFileManager: FileManager {
    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        throw NSError(domain: "VolumeSourceScannerTests", code: 1)
    }
}

private final class FailingDeletionFileManager: RemovingOnlyFileManager {
    private let failingPath: String

    init(failingURL: URL) {
        self.failingPath = failingURL.path(percentEncoded: false)
        super.init()
    }

    override func removeItem(at url: URL) throws {
        if url.path(percentEncoded: false) == failingPath {
            throw NSError(domain: "VolumeSourceScannerTests", code: 2)
        }

        try super.removeItem(at: url)
    }
}
