import SwiftUI

struct InspectorView: View {
    let capture: LogicalCapture?
    let duplicateState: CaptureDuplicateState?
    let unknownFolder: UnknownFolder?
    @Binding var showHelperFiles: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let capture {
                    CaptureInspectorContent(
                        capture: capture,
                        duplicateState: duplicateState,
                        showHelperFiles: $showHelperFiles
                    )
                } else if let unknownFolder {
                    UnknownFolderInspectorContent(unknownFolder: unknownFolder)
                } else {
                    InspectorEmptyStateView()
                }
            }
            .padding(24)
        }
        .navigationTitle("Inspector")
    }
}

private struct CaptureInspectorContent: View {
    let capture: LogicalCapture
    let duplicateState: CaptureDuplicateState?
    @Binding var showHelperFiles: Bool

    var body: some View {
        let visibleMemberFiles = capture.visibleMemberFiles(showHelperFiles: showHelperFiles)

        VStack(alignment: .leading, spacing: 18) {
            CapturePreviewSection(
                thumbnailFileURL: capture.preferredThumbnailAsset?.fileURL,
                previewFileURL: capture.preferredPreviewAsset?.fileURL
            )

            CaptureTitleSection(capture: capture, duplicateState: duplicateState)
            CaptureSummarySection(capture: capture, visibleMemberFiles: visibleMemberFiles, showHelperFiles: showHelperFiles)
            CaptureMetadataSection(sourceAsset: capture.preferredMetadataAsset)

            Toggle("Show helper files", isOn: $showHelperFiles)
                .toggleStyle(.switch)

            MemberFilesSection(files: visibleMemberFiles)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CapturePreviewSection: View {
    let thumbnailFileURL: URL?
    let previewFileURL: URL?

    var body: some View {
        CaptureThumbnailView(
            thumbnailFileURL: thumbnailFileURL,
            previewFileURL: previewFileURL,
            size: CGSize(width: 320, height: 196),
            cornerRadius: 14,
            previewPresentation: .inlinePlayableVideo
        )
    }
}

private struct CaptureTitleSection: View {
    let capture: LogicalCapture
    let duplicateState: CaptureDuplicateState?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capture.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            if let duplicateState, let duplicateStatus = CaptureDisplayFormatter.duplicateStatus(duplicateState) {
                Text(duplicateStatus)
                    .font(.subheadline)
                    .foregroundStyle(duplicateState == .duplicate ? .orange : .secondary)
            }
        }
    }
}

private struct CaptureSummarySection: View {
    let capture: LogicalCapture
    let visibleMemberFiles: [SourceAssetFile]
    let showHelperFiles: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                MetadataRow("Type", value: kindText)
                MetadataRow("Date", value: CaptureDisplayFormatter.timestamp(capture.primaryAsset?.modificationDate))
                MetadataRow("Size", value: CaptureDisplayFormatter.fileSize(capture.totalSize))
                MetadataRow("Duration", value: capture.totalDuration.map(CaptureDisplayFormatter.duration))
                MetadataRow("Dimensions", value: CaptureDisplayFormatter.dimensions(capture.primaryAsset?.pixelSize))
                MetadataRow("Members", value: memberCountText)
            }
        } label: {
            Text("Summary")
        }
    }

    private var memberCountText: String {
        let helperFileCount = capture.helperFiles.count
        guard helperFileCount > 0, !showHelperFiles else {
            let fileLabel = capture.memberFiles.count == 1 ? "file" : "files"
            return "\(capture.memberFiles.count) \(fileLabel)"
        }

        return "\(visibleMemberFiles.count) shown · \(capture.memberFiles.count) total"
    }

    private var kindText: String {
        switch capture.primaryAsset?.classification {
        case .image:
            return "Photo"
        case .video:
            return "Video"
        case .sidecar:
            return "Sidecar"
        case .unknown, .none:
            return "Capture"
        }
    }
}

private struct CaptureMetadataSection: View {
    let sourceAsset: SourceAssetFile?

    @State private var loadState: MetadataLoadState = .idle

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                switch loadState {
                case .idle, .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Loading metadata...")
                            .foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("No media metadata available for this capture.")
                        .foregroundStyle(.secondary)
                case .loaded(let metadata):
                    CaptureMetadataRowsView(metadata: metadata)
                }
            }
        } label: {
            Text("Metadata")
        }
        .task(id: sourceAsset?.id) {
            await loadMetadata()
        }
    }

    @MainActor
    private func loadMetadata() async {
        guard let sourceAsset else {
            loadState = .unavailable
            return
        }

        loadState = .loading

        let fileURL = sourceAsset.fileURL
        let metadata = await Task.detached(priority: .utility) {
            await CaptureMetadataReader.metadata(for: fileURL)
        }.value

        guard !Task.isCancelled else {
            return
        }

        loadState = .loaded(metadata)
    }
}

private enum MetadataLoadState: Equatable {
    case idle
    case loading
    case unavailable
    case loaded(CaptureMetadata)
}

private struct CaptureMetadataRowsView: View {
    let metadata: CaptureMetadata

    var body: some View {
        if metadata.rows.isEmpty {
            Text("No metadata found.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !metadata.sourceFileName.isEmpty {
                    Text(metadata.sourceFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ForEach(metadata.rows) { row in
                    MetadataRow(row.label, value: row.value)
                }
            }
        }
    }
}

private struct MemberFilesSection: View {
    let files: [SourceAssetFile]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(files) { file in
                    MemberFileRow(file: file)
                }
            }
        } label: {
            Text("Member Files")
        }
    }
}

private struct MemberFileRow: View {
    let file: SourceAssetFile

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .lineLimit(1)

                Text(file.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(CaptureDisplayFormatter.fileSize(file.fileSize))
                .foregroundStyle(.secondary)
        }
    }

    private var symbolName: String {
        switch file.classification {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .sidecar:
            return "document"
        case .unknown:
            return "questionmark.folder"
        }
    }
}

private struct UnknownFolderInspectorContent: View {
    let unknownFolder: UnknownFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UnknownFolderPreview()

            Text(unknownFolder.relativeFolderPath.isEmpty ? "Root Unknown Folder" : unknownFolder.relativeFolderPath)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Files here were not grouped into a known capture family.")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    MetadataRow("Folder", value: unknownFolder.relativeFolderPath.isEmpty ? "Root" : unknownFolder.relativeFolderPath)
                    MetadataRow("Files", value: "\(unknownFolder.files.count)")
                }
            } label: {
                Text("Summary")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(unknownFolder.files) { file in
                        HStack {
                            Text(file.fileName)
                            Spacer()
                            Text(CaptureDisplayFormatter.fileSize(file.fileSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Text("Files")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UnknownFolderPreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "folder.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 320, height: 196)
    }
}

private struct InspectorEmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a capture",
            systemImage: "sparkles.rectangle.stack",
            description: Text("Preview, metadata, and duplicate status appear here.")
        )
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct MetadataRow: View {
    private let title: String
    private let value: String?

    init(_ title: String, value: String?) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value ?? "—")
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
