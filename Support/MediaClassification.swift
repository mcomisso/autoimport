import Foundation

enum MediaClassification: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case sidecar
    case unknown

    var isRecognizedCaptureMember: Bool {
        self != .unknown
    }

    var isPrimaryCandidate: Bool {
        switch self {
        case .image, .video:
            true
        case .sidecar, .unknown:
            false
        }
    }

    static func classify(pathExtension: String) -> Self {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "dng", "arw", "orf", "raf":
            .image
        case "mp4", "mov", "m4v", "avi", "insv":
            .video
        case "thm", "lrf", "lrv", "xml", "srt", "gpx", "aae":
            .sidecar
        default:
            .unknown
        }
    }

    static func supportsVideoPreview(pathExtension: String) -> Bool {
        switch pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "avi", "insv", "lrv", "lrf":
            true
        default:
            false
        }
    }
}
