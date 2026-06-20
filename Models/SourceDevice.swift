import Foundation

struct SourceDevice: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case mountedVolume
        case imageCaptureDevice
        case folderBookmark
    }

    enum State: Hashable, Sendable {
        case ready
        case unavailable
        case scanning
    }

    let id: String
    let displayName: String
    let kind: Kind
    let rootURL: URL?
    let subtitle: String
    let state: State

    var isBrowsable: Bool {
        rootURL != nil
    }
}
