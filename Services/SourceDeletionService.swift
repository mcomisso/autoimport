import Foundation

struct SourceDeletionService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func delete(_ captures: [LogicalCapture]) -> [CaptureSourceDeletionResult] {
        captures.map { capture in
            CaptureSourceDeletionResult(
                captureID: capture.id,
                fileResults: delete(capture.memberFiles)
            )
        }
    }

    @discardableResult
    func delete(_ files: [SourceAssetFile]) -> [SourceFileDeletionResult] {
        files.map { file in
            guard fileManager.fileExists(atPath: file.fileURL.path(percentEncoded: false)) else {
                return SourceFileDeletionResult(fileID: file.id, fileURL: file.fileURL, status: .missing)
            }

            do {
                try fileManager.trashItem(at: file.fileURL, resultingItemURL: nil)
                return SourceFileDeletionResult(fileID: file.id, fileURL: file.fileURL, status: .deleted)
            } catch {
                do {
                    try fileManager.removeItem(at: file.fileURL)
                    return SourceFileDeletionResult(fileID: file.id, fileURL: file.fileURL, status: .deleted)
                } catch {
                    return SourceFileDeletionResult(
                        fileID: file.id,
                        fileURL: file.fileURL,
                        status: .failed(error.localizedDescription)
                    )
                }
            }
        }
    }
}

struct CaptureSourceDeletionResult: Equatable, Sendable {
    let captureID: String
    let fileResults: [SourceFileDeletionResult]

    var failedFileResults: [SourceFileDeletionResult] {
        fileResults.filter(\.status.isFailure)
    }
}

struct SourceFileDeletionResult: Equatable, Sendable {
    let fileID: String
    let fileURL: URL
    let status: SourceFileDeletionStatus

    var wasDeleted: Bool {
        status == .deleted
    }
}

enum SourceFileDeletionStatus: Equatable, Sendable {
    case deleted
    case missing
    case failed(String)

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}
