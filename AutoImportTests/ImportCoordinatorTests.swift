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

    @Test
    func planReservesNamesAcrossCapturesAndExecutionUsesPlannedURLs() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let firstURL = try sandbox.writeSourceFile(named: "CameraA/CLIP_0010.MP4", data: Data("first".utf8))
        let secondURL = try sandbox.writeSourceFile(named: "CameraB/CLIP_0010.MP4", data: Data("second".utf8))
        let captures = [makeSingleFileCapture(fileURL: firstURL), makeSingleFileCapture(fileURL: secondURL)]
        let coordinator = ImportCoordinator()

        let plan = try coordinator.planCaptures(
            captures,
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )

        #expect(plan.totalBytes == captures.reduce(Int64(0)) { $0 + $1.totalSize })
        #expect(plan.captures[0].files[0].action == .copy)
        #expect(plan.captures[1].files[0].action == .rename)
        #expect(plan.captures[0].files[0].destinationURL.lastPathComponent == "CLIP_0010.MP4")
        #expect(plan.captures[1].files[0].destinationURL.lastPathComponent == "CLIP_0010 2.MP4")

        let result = coordinator.importCaptures(plan)

        #expect(result.captureResults.map(\.status) == [.imported, .imported])
        #expect(result.captureResults[0].importedURLs == plan.captures[0].files.map(\.destinationURL))
        #expect(result.captureResults[1].importedURLs == plan.captures[1].files.map(\.destinationURL))
        #expect(try Data(contentsOf: plan.captures[0].files[0].destinationURL) == Data("first".utf8))
        #expect(try Data(contentsOf: plan.captures[1].files[0].destinationURL) == Data("second".utf8))
    }

    @Test
    func repeatedFilenameCollisionsDoNotRecheckEarlierSuffixes() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        for suffix in 2...5 {
            _ = try sandbox.writeDestinationFile(named: "DUP \(suffix).MP4", data: Data("existing".utf8))
        }
        _ = try sandbox.writeDestinationFile(named: "DUP.MP4", data: Data("existing".utf8))

        let captures = try (0..<40).map { index in
            let fileURL = try sandbox.writeSourceFile(
                named: "Camera\(index)/DUP.MP4",
                data: Data(repeating: UInt8(index), count: index + 10)
            )
            return makeSingleFileCapture(fileURL: fileURL)
        }
        let fileManager = FileExistenceCountingFileManager()

        let plan = try ImportCoordinator(fileManager: fileManager).planCaptures(
            captures,
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )

        #expect(plan.captures.map { $0.files[0].destinationURL.lastPathComponent }
            == (6...45).map { "DUP \($0).MP4" })
        #expect(fileManager.fileExistenceChecks < 150)
    }

    @Test(arguments: [false, true])
    func overwritePlanPreservesBothCapturesWithTheSameFilename(destinationInitiallyExists: Bool) throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let firstData = Data("first capture".utf8)
        let secondData = Data("second capture".utf8)
        let firstURL = try sandbox.writeSourceFile(named: "CameraA/CLIP_0015.MP4", data: firstData)
        let secondURL = try sandbox.writeSourceFile(named: "CameraB/CLIP_0015.MP4", data: secondData)
        if destinationInitiallyExists {
            _ = try sandbox.writeDestinationFile(named: "CLIP_0015.MP4", data: Data("old capture".utf8))
        }

        let coordinator = ImportCoordinator()
        let plan = try coordinator.planCaptures(
            [makeSingleFileCapture(fileURL: firstURL), makeSingleFileCapture(fileURL: secondURL)],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: true
        )

        #expect(plan.captures[0].files[0].action == (destinationInitiallyExists ? .replace : .copy))
        #expect(plan.captures[1].files[0].action == .rename)
        #expect(plan.captures[0].files[0].destinationURL.lastPathComponent == "CLIP_0015.MP4")
        #expect(plan.captures[1].files[0].destinationURL.lastPathComponent == "CLIP_0015 2.MP4")

        let result = coordinator.importCaptures(plan)

        #expect(result.captureResults.map(\.status) == [.imported, .imported])
        #expect(result.captureResults.allSatisfy { $0.isDeleteEligible })
        #expect(try Data(contentsOf: plan.captures[0].files[0].destinationURL) == firstData)
        #expect(try Data(contentsOf: plan.captures[1].files[0].destinationURL) == secondData)
    }

    @Test
    func executionDoesNotOverwriteDestinationCreatedAfterPlanning() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceURL = try sandbox.writeSourceFile(named: "Camera/CLIP_0011.MP4", data: Data("source".utf8))
        let coordinator = ImportCoordinator()
        let plan = try coordinator.planCaptures(
            [makeSingleFileCapture(fileURL: sourceURL)],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )
        let destinationURL = plan.captures[0].files[0].destinationURL
        let externalData = Data("external".utf8)
        try externalData.write(to: destinationURL)

        let result = coordinator.importCaptures(plan)

        #expect(result.captureResults[0].status == .failed)
        #expect(try Data(contentsOf: destinationURL) == externalData)
    }

    @Test
    func planShowsDuplicateSkipAndExcludesItsBytes() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceURL = try sandbox.writeSourceFile(named: "Camera/CLIP_0012.MP4", data: Data("same".utf8))
        _ = try sandbox.writeDestinationFile(named: "CLIP_0012.MP4", data: Data("same".utf8))
        let capture = makeSingleFileCapture(fileURL: sourceURL)
        let coordinator = ImportCoordinator()
        let plan = try coordinator.planCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )

        #expect(plan.captures[0].duplicateState == .duplicate)
        #expect(plan.captures[0].skipsDuplicate)
        #expect(plan.captures[0].files.isEmpty)
        #expect(plan.totalBytes == 0)
        #expect(coordinator.importCaptures(plan).captureResults[0].status == .skippedDuplicate)
    }

    @Test
    func previewPlanReadsDestinationChangesAfterDuplicateDetection() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceURL = try sandbox.writeSourceFile(named: "Camera/CLIP_0016.MP4", data: Data("same".utf8))
        try setModificationDate(date, for: sourceURL)
        let capture = makeSingleFileCapture(fileURL: sourceURL)
        let coordinator = ImportCoordinator()

        let initialIndex = try DestinationFingerprintIndex.buildForImportDestinations(
            captures: [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera"
        )
        #expect(initialIndex.duplicateState(for: capture) == .unique)

        let destinationURL = try sandbox.writeDestinationFile(named: "CLIP_0016.MP4", data: Data("same".utf8))
        try setModificationDate(date, for: destinationURL)
        let addedFilePlan = try coordinator.planCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )
        #expect(addedFilePlan.captures[0].skipsDuplicate)

        try FileManager.default.removeItem(at: destinationURL)
        let removedFilePlan = try coordinator.planCaptures(
            [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )
        #expect(removedFilePlan.captures[0].duplicateState == .unique)
        #expect(removedFilePlan.captures[0].files[0].action == .copy)
    }

    @Test
    func staleDuplicatePlanDoesNotReportSkippedAfterDestinationRemoval() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceURL = try sandbox.writeSourceFile(named: "Camera/CLIP_0013.MP4", data: Data("same".utf8))
        let destinationURL = try sandbox.writeDestinationFile(named: "CLIP_0013.MP4", data: Data("same".utf8))
        let coordinator = ImportCoordinator()
        let plan = try coordinator.planCaptures(
            [makeSingleFileCapture(fileURL: sourceURL)],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: false
        )
        try FileManager.default.removeItem(at: destinationURL)

        let result = coordinator.importCaptures(plan)

        #expect(result.captureResults[0].status == .failed)
        #expect(!result.captureResults[0].isDeleteEligible)
    }

    @Test
    func staleOverwritePlanPreservesChangedDestination() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceURL = try sandbox.writeSourceFile(named: "Camera/CLIP_0014.MP4", data: Data("source".utf8))
        let destinationURL = try sandbox.writeDestinationFile(named: "CLIP_0014.MP4", data: Data("original".utf8))
        let coordinator = ImportCoordinator()
        let plan = try coordinator.planCaptures(
            [makeSingleFileCapture(fileURL: sourceURL)],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "Camera",
            overwriteDuplicates: true
        )
        let changedData = Data("changed destination".utf8)
        try changedData.write(to: destinationURL)

        let result = coordinator.importCaptures(plan)

        #expect(plan.captures[0].files[0].action == .replace)
        #expect(result.captureResults[0].status == .failed)
        #expect(try Data(contentsOf: destinationURL) == changedData)
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

private final class FileExistenceCountingFileManager: FileManager {
    private(set) var fileExistenceChecks = 0

    override func fileExists(atPath path: String) -> Bool {
        fileExistenceChecks += 1
        return super.fileExists(atPath: path)
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
