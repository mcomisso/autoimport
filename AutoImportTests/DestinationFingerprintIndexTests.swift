import Foundation
import Testing

@testable import AutoImport

struct DestinationFingerprintIndexTests {
    @Test
    func matchesFilesByNameSizeAndModificationDate() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        let destinationFileURL = try sandbox.writeDestinationFile(
            named: "Imports/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        try setModificationDate(modificationDate, for: sourceFileURL)
        try setModificationDate(modificationDate, for: destinationFileURL)

        let index = try DestinationFingerprintIndex.build(rootURL: sandbox.destinationURL)
        let match = index.match(for: makeAsset(sourceFileURL, sourceID: "camera"))

        #expect(match != nil)
    }

    @Test
    func rejectsFilesWithDifferentSize() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        _ = try sandbox.writeDestinationFile(
            named: "Imports/CLIP_0001.MP4",
            data: Data("video-larger".utf8)
        )

        let index = try DestinationFingerprintIndex.build(rootURL: sandbox.destinationURL)
        let match = index.match(for: makeAsset(sourceFileURL, sourceID: "camera"))

        #expect(match == nil)
    }

    @Test
    func rejectsFilesThatOnlyShareSize() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        _ = try sandbox.writeDestinationFile(
            named: "Imports/CLIP_9999.MP4",
            data: Data("video-a".utf8)
        )

        let index = try DestinationFingerprintIndex.build(rootURL: sandbox.destinationURL)
        let match = index.match(for: makeAsset(sourceFileURL, sourceID: "camera"))

        #expect(match == nil)
    }

    @Test
    func rejectsFilesWithSameNameAndSizeButDifferentModificationDate() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        let destinationFileURL = try sandbox.writeDestinationFile(
            named: "Imports/CLIP_0001.MP4",
            data: Data("video-a".utf8)
        )
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_000), for: sourceFileURL)
        try setModificationDate(Date(timeIntervalSince1970: 1_700_003_600), for: destinationFileURL)

        let index = try DestinationFingerprintIndex.build(rootURL: sandbox.destinationURL)
        let match = index.match(for: makeAsset(sourceFileURL, sourceID: "camera"))

        #expect(match == nil)
    }

    @Test
    func marksCaptureAsPartialWhenOnlySomeMembersExistInDestination() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let primaryModificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let primaryURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0002.MP4",
            data: Data("video-main".utf8)
        )
        let sidecarURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0002.THM",
            data: Data("sidecar".utf8)
        )
        _ = try sandbox.writeDestinationFile(
            named: "Imports/CLIP_0002.MP4",
            data: Data("video-main".utf8)
        )
        try setModificationDate(primaryModificationDate, for: primaryURL)
        try setModificationDate(
            primaryModificationDate,
            for: sandbox.destinationURL.appending(path: "Imports/CLIP_0002.MP4")
        )

        let capture = LogicalCapture(
            id: "capture",
            displayName: "CLIP_0002",
            primaryAsset: makeAsset(primaryURL, sourceID: "camera"),
            memberFiles: [
                makeAsset(primaryURL, sourceID: "camera"),
                makeAsset(sidecarURL, sourceID: "camera"),
            ],
            companionFiles: [makeAsset(sidecarURL, sourceID: "camera")],
            multipartSegments: [],
            totalDuration: 10
        )

        let index = try DestinationFingerprintIndex.build(rootURL: sandbox.destinationURL)

        #expect(index.duplicateState(for: capture) == .partial)
    }

    @Test
    func importDestinationIndexIgnoresUnplannedSubtrees() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0008.MP4",
            data: Data("video-a".utf8)
        )
        let archivedFileURL = try sandbox.writeDestinationFile(
            named: "Archive/CLIP_0008.MP4",
            data: Data("video-a".utf8)
        )
        try setModificationDate(modificationDate, for: sourceFileURL)
        try setModificationDate(modificationDate, for: archivedFileURL)

        let sourceAsset = makeAsset(sourceFileURL, sourceID: "camera")
        let capture = LogicalCapture(
            id: "capture",
            displayName: "CLIP_0008",
            primaryAsset: sourceAsset,
            memberFiles: [sourceAsset],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
        let index = try DestinationFingerprintIndex.buildForImportDestinations(
            captures: [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .flat,
            cameraName: "DJI"
        )

        #expect(index.match(for: sourceAsset) == nil)
    }

    @Test
    func importDestinationIndexMatchesPlannedCameraDateDirectory() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let sourceFileURL = try sandbox.writeSourceFile(
            named: "DCIM/DJI_001/CLIP_0009.MP4",
            data: Data("video-a".utf8)
        )
        try setModificationDate(modificationDate, for: sourceFileURL)

        let sourceAsset = makeAsset(sourceFileURL, sourceID: "camera")
        let capture = LogicalCapture(
            id: "capture",
            displayName: "CLIP_0009",
            primaryAsset: sourceAsset,
            memberFiles: [sourceAsset],
            companionFiles: [],
            multipartSegments: [],
            totalDuration: nil
        )
        let plannedDirectory = DestinationImportPlanner.destinationDirectory(
            for: capture,
            destinationRoot: sandbox.destinationURL,
            organizationMode: .byCameraAndDate,
            cameraName: "DJI Camera"
        )
        let plannedFileURL = plannedDirectory.appendingPathComponent("CLIP_0009.MP4", isDirectory: false)
        try FileManager.default.createDirectory(at: plannedDirectory, withIntermediateDirectories: true)
        try Data("video-a".utf8).write(to: plannedFileURL)
        try setModificationDate(modificationDate, for: plannedFileURL)

        let index = try DestinationFingerprintIndex.buildForImportDestinations(
            captures: [capture],
            destinationRoot: sandbox.destinationURL,
            organizationMode: .byCameraAndDate,
            cameraName: "DJI Camera"
        )

        #expect(resolvedPath(index.match(for: sourceAsset)) == resolvedPath(plannedFileURL))
    }

    private func setModificationDate(_ date: Date, for fileURL: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path(percentEncoded: false))
    }

    private func resolvedPath(_ fileURL: URL?) -> String? {
        fileURL?.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    private func makeAsset(_ fileURL: URL, sourceID: String) -> SourceAssetFile {
        let values = try! fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SourceAssetFile(
            sourceID: sourceID,
            relativePath: fileURL.lastPathComponent,
            fileURL: fileURL,
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast,
            classification: .classify(pathExtension: fileURL.pathExtension),
            duration: nil,
            pixelSize: nil
        )
    }

    private func makeSandbox() throws -> DuplicateSandbox {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let sourceURL = rootURL.appending(path: "Source", directoryHint: .isDirectory)
        let destinationURL = rootURL.appending(path: "Destination", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        return DuplicateSandbox(rootURL: rootURL, sourceURL: sourceURL, destinationURL: destinationURL)
    }
}

private struct DuplicateSandbox {
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
