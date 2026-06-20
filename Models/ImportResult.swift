import Foundation

enum CaptureImportStatus: Equatable, Sendable {
    case imported
    case skippedDuplicate
    case failed
}

struct CaptureImportResult: Equatable, Sendable {
    let captureID: String
    let status: CaptureImportStatus
    let importedURLs: [URL]
    let isDeleteEligible: Bool
}

struct ImportSessionResult: Equatable, Sendable {
    let captureResults: [CaptureImportResult]
}

struct ImportProgress: Equatable, Sendable {
    let completedCaptures: Int
    let totalCaptures: Int
    let completedBytes: Int64
    let totalBytes: Int64
    let currentCaptureName: String?

    var fractionComplete: Double {
        guard totalBytes > 0 else {
            guard totalCaptures > 0 else { return 0 }
            return Double(completedCaptures) / Double(totalCaptures)
        }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}
