import AppKit
import AVKit
import QuickLookThumbnailing
import SwiftUI

private struct CachedCaptureImage: @unchecked Sendable {
    let image: NSImage
    let estimatedByteCount: Int
}

private struct CaptureThumbnailPreparedSource: Hashable, Sendable {
    let fileURL: URL
    let canonicalPath: String
    let pathExtension: String

    init(fileURL: URL) {
        self.fileURL = fileURL
        canonicalPath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        pathExtension = fileURL.pathExtension
    }
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

        init(source: CaptureThumbnailPreparedSource, targetSize: CGSize, scale: CGFloat, purpose: Purpose) {
            urlPath = source.canonicalPath
            pointWidth = max(1, Int(targetSize.width.rounded(.up)))
            pointHeight = max(1, Int(targetSize.height.rounded(.up)))
            displayScale = max(1, (Double(scale) * 100).rounded() / 100)
            self.purpose = purpose
        }
    }

    private let maximumEntryCount = 96
    private let maximumTotalByteCount = 32 * 1024 * 1024
    private var images: [Key: CachedCaptureImage] = [:]
    private var recentlyUsedKeys: [Key] = []
    private var totalByteCount = 0
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
        if let existingImage = images[key] {
            totalByteCount -= existingImage.estimatedByteCount
        }

        images[key] = image
        totalByteCount += image.estimatedByteCount
        markRecentlyUsed(key)

        while shouldEvictEntries, let keyToRemove = recentlyUsedKeys.first {
            recentlyUsedKeys.removeFirst()
            if let removedImage = images.removeValue(forKey: keyToRemove) {
                totalByteCount -= removedImage.estimatedByteCount
            }
            inFlightLoads[keyToRemove] = nil
        }
    }

    private var shouldEvictEntries: Bool {
        recentlyUsedKeys.count > maximumEntryCount
            || (totalByteCount > maximumTotalByteCount && recentlyUsedKeys.count > 1)
    }

    private func markRecentlyUsed(_ key: Key) {
        recentlyUsedKeys.removeAll { $0 == key }
        recentlyUsedKeys.append(key)
    }
}

private struct CaptureThumbnailTaskID: Hashable, Sendable {
    let purpose: CaptureThumbnailPreviewCache.Purpose
    let pointWidth: Int
    let pointHeight: Int
    let urlPath: String?

    init(
        source: CaptureThumbnailPreparedSource?,
        targetSize: CGSize,
        purpose: CaptureThumbnailPreviewCache.Purpose
    ) {
        self.purpose = purpose
        pointWidth = max(1, Int(targetSize.width.rounded(.up)))
        pointHeight = max(1, Int(targetSize.height.rounded(.up)))
        urlPath = source?.canonicalPath
    }
}

struct CaptureThumbnailView: View {
    private let thumbnailSource: CaptureThumbnailPreparedSource?
    private let effectivePreviewSource: CaptureThumbnailPreparedSource?
    private let size: CGSize
    private let cornerRadius: CGFloat
    private let previewPresentation: CaptureThumbnailPreviewPresentation
    private let previewDisplaySize: CGSize
    private let isPreviewVideo: Bool
    private let thumbnailTaskID: CaptureThumbnailTaskID
    private let previewTaskID: CaptureThumbnailTaskID

    @State private var image: NSImage?
    @State private var loadedThumbnailID: CaptureThumbnailTaskID?
    @State private var isShowingPreview = false
    @State private var previewImage: NSImage?
    @State private var loadedPreviewID: CaptureThumbnailTaskID?
    @State private var isLoadingPreviewImage = false
    @State private var player: AVPlayer?

    private static let imageCache = CaptureThumbnailPreviewCache()

    init(
        thumbnailFileURL: URL?,
        previewFileURL: URL?,
        size: CGSize = CGSize(width: 88, height: 58),
        cornerRadius: CGFloat = 10,
        previewPresentation: CaptureThumbnailPreviewPresentation = .popover
    ) {
        let preparedThumbnailSource = thumbnailFileURL.map(CaptureThumbnailPreparedSource.init(fileURL:))
        let preparedPreviewSource = previewFileURL.map(CaptureThumbnailPreparedSource.init(fileURL:))
        let effectivePreviewSource = preparedPreviewSource ?? preparedThumbnailSource
        let thumbnailSource = preparedThumbnailSource ?? effectivePreviewSource
        let previewDisplaySize = Self.previewDisplaySize(for: size)

        self.thumbnailSource = thumbnailSource
        self.effectivePreviewSource = effectivePreviewSource
        self.size = size
        self.cornerRadius = cornerRadius
        self.previewPresentation = previewPresentation
        self.previewDisplaySize = previewDisplaySize
        isPreviewVideo = effectivePreviewSource.map {
            MediaClassification.supportsVideoPreview(pathExtension: $0.pathExtension)
        } ?? false
        thumbnailTaskID = CaptureThumbnailTaskID(
            source: thumbnailSource,
            targetSize: size,
            purpose: .thumbnail
        )
        previewTaskID = CaptureThumbnailTaskID(
            source: effectivePreviewSource,
            targetSize: previewDisplaySize,
            purpose: .preview
        )
    }

    var body: some View {
        Group {
            if previewPresentation == .inlinePlayableVideo, isPreviewVideo, let effectivePreviewSource {
                PreviewVideoPlayerView(
                    source: effectivePreviewSource,
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
        guard let thumbnailSource else {
            return "photo.on.rectangle.angled"
        }

        if MediaClassification.supportsVideoPreview(pathExtension: thumbnailSource.pathExtension) {
            return "video.fill"
        }

        return "photo.fill"
    }

    @ViewBuilder
    private var popoverThumbnail: some View {
        if effectivePreviewSource != nil {
            Button {
                isShowingPreview = true
            } label: {
                thumbnailBody
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPreview) {
                previewBody
            }
            .onChange(of: isShowingPreview) { _, isShowingPreview in
                if !isShowingPreview {
                    clearPreviewState()
                }
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

            if effectivePreviewSource != nil {
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
        if isPreviewVideo, let effectivePreviewSource {
            PreviewVideoPlayerView(
                source: effectivePreviewSource,
                width: previewDisplaySize.width,
                height: previewDisplaySize.height,
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
            .frame(width: previewDisplaySize.width, height: previewDisplaySize.height)
            .padding(16)
            .task(id: previewTaskID) {
                await loadPreviewImage(taskID: previewTaskID)
            }
        }
    }

    private static func previewDisplaySize(for size: CGSize) -> CGSize {
        CGSize(width: max(size.width * 5.5, 420), height: max(size.height * 5.5, 260))
    }

    private var previewSymbolName: String {
        isPreviewVideo ? "play.fill" : "arrow.up.left.and.arrow.down.right"
    }

    @MainActor
    private func loadThumbnailImage(taskID: CaptureThumbnailTaskID) async {
        guard let thumbnailSource else {
            image = nil
            loadedThumbnailID = nil
            return
        }

        let loadedImage = await Self.cachedImage(for: thumbnailSource, targetSize: size, purpose: .thumbnail)
        guard !Task.isCancelled else {
            return
        }

        image = loadedImage
        loadedThumbnailID = loadedImage == nil ? nil : taskID
    }

    @MainActor
    private func loadPreviewImage(taskID: CaptureThumbnailTaskID) async {
        guard let effectivePreviewSource, !isPreviewVideo else {
            previewImage = nil
            loadedPreviewID = nil
            isLoadingPreviewImage = false
            return
        }

        previewImage = nil
        loadedPreviewID = nil
        isLoadingPreviewImage = true

        let loadedImage = await Self.cachedImage(for: effectivePreviewSource, targetSize: previewDisplaySize, purpose: .preview)
        guard !Task.isCancelled else {
            return
        }

        previewImage = loadedImage
        loadedPreviewID = loadedImage == nil ? nil : taskID
        isLoadingPreviewImage = false
    }

    @MainActor
    private func clearPreviewState() {
        previewImage = nil
        loadedPreviewID = nil
        isLoadingPreviewImage = false
        player?.pause()
        player = nil
    }

    private static func cachedImage(
        for source: CaptureThumbnailPreparedSource,
        targetSize: CGSize,
        purpose: CaptureThumbnailPreviewCache.Purpose
    ) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let key = CaptureThumbnailPreviewCache.Key(
            source: source,
            targetSize: targetSize,
            scale: scale,
            purpose: purpose
        )

        let cachedImage = await imageCache.image(for: key) {
            guard !Task.isCancelled else {
                return nil
            }

            return await quickLookImage(for: source, key: key)
        }

        return cachedImage?.image
    }

    private static func quickLookImage(
        for source: CaptureThumbnailPreparedSource,
        key: CaptureThumbnailPreviewCache.Key
    ) async -> CachedCaptureImage? {
        guard !Task.isCancelled else {
            return nil
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: source.fileURL,
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

        return CachedCaptureImage(
            image: image,
            estimatedByteCount: estimatedByteCount(for: image, key: key)
        )
    }

    private static func estimatedByteCount(for image: NSImage, key: CaptureThumbnailPreviewCache.Key) -> Int {
        let requestedPixelCount = max(1, key.pointWidth)
            * max(1, key.pointHeight)
            * max(1, Int(key.displayScale.rounded(.up)))
            * max(1, Int(key.displayScale.rounded(.up)))
        let representationPixelCount = image.representations.reduce(0) { pixelCount, representation in
            pixelCount + max(0, representation.pixelsWide) * max(0, representation.pixelsHigh)
        }
        let pixelCount = max(requestedPixelCount, representationPixelCount)
        return max(1, pixelCount * 4)
    }
}

enum CaptureThumbnailPreviewPresentation {
    case popover
    case inlinePlayableVideo
}

private struct PreviewVideoPlayerView: View {
    let source: CaptureThumbnailPreparedSource
    let width: CGFloat
    let height: CGFloat
    let autoplays: Bool
    @Binding var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                AVPlayerViewRepresentable(player: player)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .task(id: source.canonicalPath) {
            let activePlayer: AVPlayer
            if let player, (player.currentItem?.asset as? AVURLAsset)?.url == source.fileURL {
                activePlayer = player
            } else {
                let newPlayer = AVPlayer(url: source.fileURL)
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

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player?.pause()
        playerView.player = nil
    }
}
