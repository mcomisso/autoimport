import Foundation
import Testing

@testable import AutoImport

struct ImportCoordinatorTests {
    @Test
    func importsAllCaptureMembersAndMarksCaptureDeleteEligible() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let primaryURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0003.MP4", data: Data("video".utf8))
        let sidecarURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0003.THM", data: Data("sidecar".utf8))
        let capture = makeCapture(primaryURL: primaryURL, sidecarURL: sidecarURL)

        let result = try ImportCoordinator().importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false
        )

        #expect(result.captureResults.count == 1)
        #expect(result.captureResults[0].status == .imported)
        #expect(result.captureResults[0].isDeleteEligible)
        #expect(FileManager.default.fileExists(atPath: sandbox.destinationURL.appending(path: "CLIP_0003.MP4").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: sandbox.destinationURL.appending(path: "CLIP_0003.THM").path(percentEncoded: false)))
    }

    @Test
    func reportsCopiedByteProgressBeforeCaptureCompletes() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let fileSize = (5 * 1024 * 1024) + 123
        let sourceURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0100.MP4",
            data: Data(repeating: 0x5A, count: fileSize)
        )
        let capture = makeSingleFileCapture(fileURL: sourceURL)
        let progressRecorder = ProgressRecorder()

        let result = try ImportCoordinator().importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false,
            onProgress: { progress in
                progressRecorder.append(progress)
            }
        )

        let progressUpdates = progressRecorder.values()

        #expect(result.captureResults[0].status == .imported)
        #expect(progressUpdates.contains { progress in
            progress.completedCaptures == 0
                && progress.completedBytes > 0
                && progress.completedBytes < progress.totalBytes
        })
        #expect(progressUpdates.last?.completedCaptures == 1)
        #expect(progressUpdates.last?.completedBytes == Int64(fileSize))
        #expect(progressUpdates.last?.currentCaptureName == nil)
    }

    @Test
    func skipsDuplicateCaptureUnlessOverwriteIsExplicitlyEnabled() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let primaryURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0004.MP4", data: Data("video".utf8))
        let sidecarURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0004.THM", data: Data("sidecar".utf8))
        _ = try sandbox.writeDestinationFile(named: "CLIP_0004.MP4", data: Data("video".utf8))
        _ = try sandbox.writeDestinationFile(named: "CLIP_0004.THM", data: Data("sidecar".utf8))

        let capture = makeCapture(primaryURL: primaryURL, sidecarURL: sidecarURL)
        let result = try ImportCoordinator().importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false
        )

        #expect(result.captureResults[0].status == .skippedDuplicate)
        #expect(!result.captureResults[0].isDeleteEligible)
    }

    @Test
    func excludesSkippedDuplicateBytesFromProgressTotal() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let duplicateSourceURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0101.MP4", data: Data("duplicate".utf8))
        _ = try sandbox.writeDestinationFile(named: "CLIP_0101.MP4", data: Data("duplicate".utf8))
        let uniqueSourceURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0102.MP4", data: Data("unique import".utf8))
        let duplicateCapture = makeSingleFileCapture(fileURL: duplicateSourceURL)
        let uniqueCapture = makeSingleFileCapture(fileURL: uniqueSourceURL)
        let progressRecorder = ProgressRecorder()

        let result = try ImportCoordinator().importCaptures(
            [duplicateCapture, uniqueCapture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false,
            onProgress: { progress in
                progressRecorder.append(progress)
            }
        )

        let progressUpdates = progressRecorder.values()

        #expect(result.captureResults.map(\.status) == [.skippedDuplicate, .imported])
        #expect(progressUpdates.last?.totalBytes == uniqueCapture.totalSize)
        #expect(progressUpdates.last?.completedBytes == uniqueCapture.totalSize)
    }

    @Test
    func failsCaptureWhenAnyMemberFileCannotBeCopied() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let primaryURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0005.MP4", data: Data("video".utf8))
        let missingSidecarURL = sandbox.sourceURL.appending(path: "DCIM/DJI_001/CLIP_0005.THM")
        let capture = makeCapture(primaryURL: primaryURL, sidecarURL: missingSidecarURL)

        let result = try ImportCoordinator().importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false
        )

        #expect(result.captureResults[0].status == .failed)
        #expect(!result.captureResults[0].isDeleteEligible)
        #expect(!FileManager.default.fileExists(atPath: sandbox.destinationURL.appending(path: "CLIP_0005.MP4").path(percentEncoded: false)))
    }

    @Test
    func overwriteFailurePreservesExistingDestination() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let originalData = Data("original destination".utf8)
        let replacementData = Data("replacement source".utf8)
        let sourceURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0006.MP4", data: replacementData)
        let destinationURL = try sandbox.writeDestinationFile(named: "CLIP_0006.MP4", data: originalData)
        let capture = makeSingleFileCapture(fileURL: sourceURL)
        let fileManager = ReplacementMoveFailingFileManager(failingDestinationURL: destinationURL)

        let result = try ImportCoordinator(fileManager: fileManager).importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: true
        )

        #expect(result.captureResults[0].status == .failed)
        #expect(!result.captureResults[0].isDeleteEligible)
        #expect(try Data(contentsOf: destinationURL) == originalData)
    }

    @Test
    func unrelatedDestinationSubtreesDoNotBlockFlatImports() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let sourceURL = try sandbox.writeSourceFile(named: "DCIM/DJI_001/CLIP_0007.MP4", data: Data("video".utf8))
        let archivedURL = try sandbox.writeDestinationFile(named: "Archive/CLIP_0007.MP4", data: Data("video".utf8))
        try setModificationDate(modificationDate, for: sourceURL)
        try setModificationDate(modificationDate, for: archivedURL)
        let capture = makeSingleFileCapture(fileURL: sourceURL)

        let result = try ImportCoordinator().importCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI",
            overwriteDuplicates: false
        )

        #expect(result.captureResults[0].status == .imported)
        #expect(FileManager.default.fileExists(atPath: sandbox.destinationURL.appending(path: "CLIP_0007.MP4").path(percentEncoded: false)))
    }

    private func makeCapture(primaryURL: URL, sidecarURL: URL) -> LogicalCapture {
        let primaryAsset = makeAsset(primaryURL)
        let sidecarAsset = makeAsset(sidecarURL)
        return LogicalCapture(
            id: primaryAsset.fileStem,
            displayName: primaryAsset.fileStem,
            primaryAsset: primaryAsset,
            memberFiles: [primaryAsset, sidecarAsset],
            companionFiles: [sidecarAsset],
            multipartSegments: [],
            totalDuration: primaryAsset.duration
        )
    }

    private func makeSingleFileCapture(fileURL: URL) -> LogicalCapture {
        let asset = makeAsset(fileURL)
        return LogicalCapture(
            id: asset.fileStem,
            displayName: asset.fileStem,
            primaryAsset: asset,
            memberFiles: [asset],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: asset.duration
        )
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

    private func setModificationDate(_ date: Date, for fileURL: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path(percentEncoded: false))
    }

    private func makeSandbox() throws -> ImportSandbox {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceURL = rootURL.appending(path: "Source", directoryHint: .isDirectory)
        let destinationURL = rootURL.appending(path: "Destination", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        return ImportSandbox(rootURL: rootURL, sourceURL: sourceURL, destinationURL: destinationURL)
    }
}

private final class ReplacementMoveFailingFileManager: FileManager {
    private let failingDestinationPath: String

    init(failingDestinationURL: URL) {
        self.failingDestinationPath = failingDestinationURL.path(percentEncoded: false)
        super.init()
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.path(percentEncoded: false) == failingDestinationPath,
           srcURL.lastPathComponent.hasPrefix(".autoimport-copy-") {
            throw NSError(domain: "ImportCoordinatorTests", code: 1)
        }

        try super.moveItem(at: srcURL, to: dstURL)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var progressUpdates: [ImportProgress] = []

    func append(_ progress: ImportProgress) {
        lock.lock()
        defer { lock.unlock() }
        progressUpdates.append(progress)
    }

    func values() -> [ImportProgress] {
        lock.lock()
        defer { lock.unlock() }
        return progressUpdates
    }
}

private struct ImportSandbox {
    let rootURL: URL
    let sourceURL: URL
    let destinationURL: URL

    func writeSourceFile(named relativePath: String, data: Data) throws -> URL {
        try writeFile(named: relativePath, under: sourceURL, data: data)
    }

    func writeDestinationFile(named relativePath: String, data: Data) throws -> URL {
        try writeFile(named: relativePath, under: destinationURL, data: data)
    }

    private func writeFile(named relativePath: String, under rootURL: URL, data: Data) throws -> URL {
        let fileURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        return fileURL
    }
}
