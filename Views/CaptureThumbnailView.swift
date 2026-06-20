import AppKit
import AVKit
import QuickLookThumbnailing
import SwiftUI

private struct CachedCaptureImage: @unchecked Sendable {
    let image: NSImage
}

private actor CaptureThumbnailPreviewCache {
    enum Purpose: String, Sendable {
        case thumbnail
        case preview
    }

    struct Key: Hashable, Sendable {
        let urlPath: String
        let pointWidth: Int
        let pointHeight: Int
        let displayScale: Double
        let purpose: Purpose

        init(fileURL: URL, targetSize: CGSize, scale: CGFloat, purpose: Purpose) {
            urlPath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            pointWidth = max(1, Int(targetSize.width.rounded(.up)))
            pointHeight = max(1, Int(targetSize.height.rounded(.up)))
            displayScale = max(1, (Double(scale) * 100).rounded() / 100)
            self.purpose = purpose
        }
    }

    private let maximumEntryCount = 96
    private var images: [Key: CachedCaptureImage] = [:]
    private var recentlyUsedKeys: [Key] = []
    private var inFlightLoads: [Key: Task<CachedCaptureImage?, Never>] = [:]

    func image(for key: Key, load: @escaping @Sendable () async -> CachedCaptureImage?) async -> CachedCaptureImage? {
        if let cachedImage = images[key] {
            markRecentlyUsed(key)
            return cachedImage
        }

        if let inFlightLoad = inFlightLoads[key] {
            return await inFlightLoad.value
        }

        let loadTask = Task.detached(priority: .userInitiated) {
            await load()
        }
        inFlightLoads[key] = loadTask

        let loadedImage = await loadTask.value
        inFlightLoads[key] = nil

        if let loadedImage {
            store(loadedImage, for: key)
        }

        return loadedImage
    }

    private func store(_ image: CachedCaptureImage, for key: Key) {
        images[key] = image
        markRecentlyUsed(key)

        while recentlyUsedKeys.count > maximumEntryCount, let keyToRemove = recentlyUsedKeys.first {
            recentlyUsedKeys.removeFirst()
            images[keyToRemove] = nil
            inFlightLoads[keyToRemove] = nil
        }
    }

    private func markRecentlyUsed(_ key: Key) {
        recentlyUsedKeys.removeAll { $0 == key }
        recentlyUsedKeys.append(key)
    }
}

struct CaptureThumbnailView: View {
    let thumbnailFileURL: URL?
    let previewFileURL: URL?
    var size: CGSize = CGSize(width: 88, height: 58)
    var cornerRadius: CGFloat = 10
    var previewPresentation: CaptureThumbnailPreviewPresentation = .popover

    @State private var image: NSImage?
    @State private var loadedThumbnailID: String?
    @State private var isShowingPreview = false
    @State private var previewImage: NSImage?
    @State private var loadedPreviewID: String?
    @State private var isLoadingPreviewImage = false
    @State private var player: AVPlayer?

    private static let imageCache = CaptureThumbnailPreviewCache()

    var body: some View {
        Group {
            if previewPresentation == .inlinePlayableVideo, isPreviewVideo, let effectivePreviewURL {
                PreviewVideoPlayerView(
                    url: effectivePreviewURL,
                    width: size.width,
                    height: size.height,
                    autoplays: false,
                    player: $player
                )
            } else {
                popoverThumbnail
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var placeholderSymbolName: String {
        guard let fileURL = thumbnailSourceURL else {
            return "photo.on.rectangle.angled"
        }

        if MediaClassification.supportsVideoPreview(pathExtension: fileURL.pathExtension) {
            return "video.fill"
        }

        return "photo.fill"
    }

    @ViewBuilder
    private var popoverThumbnail: some View {
        if effectivePreviewURL != nil {
            Button {
                isShowingPreview = true
            } label: {
                thumbnailBody
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPreview) {
                previewBody
            }
        } else {
            thumbnailBody
        }
    }

    @ViewBuilder
    private var thumbnailBody: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary)

            if loadedThumbnailID == thumbnailTaskID, let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbolName)
                    .font(.system(size: min(size.width, size.height) * 0.35))
                    .foregroundStyle(.secondary)
            }

            if effectivePreviewURL != nil {
                Image(systemName: previewSymbolName)
                    .font(.system(size: min(size.width, size.height) * 0.24, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(8)
            }
        }
        .task(id: thumbnailTaskID) {
            await loadThumbnailImage(taskID: thumbnailTaskID)
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        let displaySize = previewDisplaySize

        if isPreviewVideo, let effectivePreviewURL {
            PreviewVideoPlayerView(
                url: effectivePreviewURL,
                width: displaySize.width,
                height: displaySize.height,
                autoplays: true,
                player: $player
            )
        } else {
            ZStack {
                if loadedPreviewID == previewTaskID, let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                } else if isLoadingPreviewImage {
                    ProgressView()
                } else {
                    ContentUnavailableView("Preview unavailable", systemImage: "eye.slash")
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
            .padding(16)
            .task(id: previewTaskID) {
                await loadPreviewImage(taskID: previewTaskID)
            }
        }
    }

    private var thumbnailSourceURL: URL? {
        thumbnailFileURL ?? effectivePreviewURL
    }

    private var effectivePreviewURL: URL? {
        previewFileURL ?? thumbnailFileURL
    }

    private var previewDisplaySize: CGSize {
        CGSize(width: max(size.width * 5.5, 420), height: max(size.height * 5.5, 260))
    }

    private var isPreviewVideo: Bool {
        guard let effectivePreviewURL else {
            return false
        }

        return MediaClassification.supportsVideoPreview(pathExtension: effectivePreviewURL.pathExtension)
    }

    private var previewSymbolName: String {
        isPreviewVideo ? "play.fill" : "arrow.up.left.and.arrow.down.right"
    }

    private var thumbnailTaskID: String {
        Self.taskID(for: thumbnailSourceURL, targetSize: size, purpose: .thumbnail)
    }

    private var previewTaskID: String {
        Self.taskID(for: effectivePreviewURL, targetSize: previewDisplaySize, purpose: .preview)
    }

    @MainActor
    private func loadThumbnailImage(taskID: String) async {
        guard let fileURL = thumbnailSourceURL else {
            image = nil
            loadedThumbnailID = nil
            return
        }

        let loadedImage = await Self.cachedImage(for: fileURL, targetSize: size, purpose: .thumbnail)
        guard !Task.isCancelled else {
            return
        }

        image = loadedImage
        loadedThumbnailID = loadedImage == nil ? nil : taskID
    }

    @MainActor
    private func loadPreviewImage(taskID: String) async {
        guard let effectivePreviewURL, !isPreviewVideo else {
            previewImage = nil
            loadedPreviewID = nil
            isLoadingPreviewImage = false
            return
        }

        previewImage = nil
        loadedPreviewID = nil
        isLoadingPreviewImage = true

        let loadedImage = await Self.cachedImage(for: effectivePreviewURL, targetSize: previewDisplaySize, purpose: .preview)
        guard !Task.isCancelled else {
            return
        }

        previewImage = loadedImage
        loadedPreviewID = loadedImage == nil ? nil : taskID
        isLoadingPreviewImage = false
    }

    private static func cachedImage(
        for fileURL: URL,
        targetSize: CGSize,
        purpose: CaptureThumbnailPreviewCache.Purpose
    ) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let key = CaptureThumbnailPreviewCache.Key(
            fileURL: fileURL,
            targetSize: targetSize,
            scale: scale,
            purpose: purpose
        )

        let cachedImage = await imageCache.image(for: key) {
            guard !Task.isCancelled else {
                return nil
            }

            return await quickLookImage(for: fileURL, key: key)
        }

        return cachedImage?.image
    }

    private static func quickLookImage(for fileURL: URL, key: CaptureThumbnailPreviewCache.Key) async -> CachedCaptureImage? {
        guard !Task.isCancelled else {
            return nil
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: CGFloat(key.pointWidth), height: CGFloat(key.pointHeight)),
            scale: CGFloat(key.displayScale),
            representationTypes: .thumbnail
        )

        let image = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }

        guard !Task.isCancelled, let image else {
            return nil
        }

        return CachedCaptureImage(image: image)
    }

    private static func taskID(
        for fileURL: URL?,
        targetSize: CGSize,
        purpose: CaptureThumbnailPreviewCache.Purpose
    ) -> String {
        guard let fileURL else {
            return "\(purpose.rawValue):none"
        }

        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let width = max(1, Int(targetSize.width.rounded(.up)))
        let height = max(1, Int(targetSize.height.rounded(.up)))
        return "\(purpose.rawValue):\(width)x\(height):\(path)"
    }
}

enum CaptureThumbnailPreviewPresentation {
    case popover
    case inlinePlayableVideo
}

private struct PreviewVideoPlayerView: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    let autoplays: Bool
    @Binding var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .task(id: url.path(percentEncoded: false)) {
            let activePlayer: AVPlayer
            if let player, (player.currentItem?.asset as? AVURLAsset)?.url == url {
                activePlayer = player
            } else {
                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                activePlayer = newPlayer
            }

            if autoplays {
                activePlayer.seek(to: .zero)
                activePlayer.play()
            } else {
                activePlayer.pause()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
