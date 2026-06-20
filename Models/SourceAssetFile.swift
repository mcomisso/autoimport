import Foundation

struct PixelSize: Hashable, Sendable {
    let width: Int
    let height: Int
}

struct SourceAssetFile: Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let relativePath: String
    let fileURL: URL
    let fileSize: Int64
    let modificationDate: Date
    let classification: MediaClassification
    let duration: TimeInterval?
    let pixelSize: PixelSize?

    init(
        id: String? = nil,
        sourceID: String,
        relativePath: String,
        fileURL: URL,
        fileSize: Int64,
        modificationDate: Date,
        classification: MediaClassification,
        duration: TimeInterval?,
        pixelSize: PixelSize?
    ) {
        self.id = id ?? "\(sourceID)::\(relativePath)"
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.classification = classification
        self.duration = duration
        self.pixelSize = pixelSize
    }

    var relativeDirectoryPath: String {
        let path = (relativePath as NSString).deletingLastPathComponent
        if path == "." || path == "/" {
            return ""
        }

        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    var fileStem: String {
        ((relativePath as NSString).deletingPathExtension as NSString).lastPathComponent
    }

    var normalizedPathExtension: String {
        fileURL.pathExtension.lowercased()
    }

    var isHelperFile: Bool {
        classification == .sidecar
    }

    var isThumbnailHelper: Bool {
        normalizedPathExtension == "thm"
    }

    var isProxyVideoHelper: Bool {
        ["lrv", "lrf"].contains(normalizedPathExtension)
    }
}
