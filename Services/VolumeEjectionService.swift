import AppKit
import Foundation

struct VolumeEjectionService {
    func eject(_ source: SourceDevice) throws {
        guard source.kind == .mountedVolume, let rootURL = source.rootURL else {
            throw VolumeEjectionError.unsupportedSource
        }

        try NSWorkspace.shared.unmountAndEjectDevice(at: rootURL)
    }
}

enum VolumeEjectionError: LocalizedError {
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "Only mounted source drives can be ejected."
        }
    }
}
