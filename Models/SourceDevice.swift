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
    let persistentVolumeID: String?

    init(
        id: String,
        displayName: String,
        kind: Kind,
        rootURL: URL?,
        subtitle: String,
        state: State,
        persistentVolumeID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.rootURL = rootURL
        self.subtitle = subtitle
        self.state = state
        self.persistentVolumeID = persistentVolumeID
    }

    var isBrowsable: Bool {
        rootURL != nil
    }
}
