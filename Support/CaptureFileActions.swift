import AppKit
import Foundation

struct CaptureFileActions: Sendable {
    var open: @MainActor @Sendable (LogicalCapture) -> Void
    var revealInFinder: @MainActor @Sendable (LogicalCapture) -> Void
    var copyFilePath: @MainActor @Sendable (LogicalCapture) -> Void

    static let live = CaptureFileActions(
        open: { capture in
            guard let url = capture.fileActionURL else {
                return
            }

            NSWorkspace.shared.open(url)
        },
        revealInFinder: { capture in
            let urls = capture.finderSelectionURLs
            guard !urls.isEmpty else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting(urls)
        },
        copyFilePath: { capture in
            guard let path = capture.fileActionURL?.path(percentEncoded: false) else {
                return
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
        }
    )
}

extension LogicalCapture {
    var fileActionURL: URL? {
        primaryAsset?.fileURL
            ?? preferredPreviewAsset?.fileURL
            ?? memberFiles.first?.fileURL
    }

    var finderSelectionURLs: [URL] {
        let memberURLs = memberFiles.map(\.fileURL)
        if !memberURLs.isEmpty {
            return memberURLs
        }

        return fileActionURL.map { [$0] } ?? []
    }
}
