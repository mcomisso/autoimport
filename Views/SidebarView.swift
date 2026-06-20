import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore
    let onRefresh: () -> Void
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh sources")

                Button(action: onAddFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Add source folder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List(selection: sourceSelection) {
                if store.sources.isEmpty {
                    Label("No cameras or folders", systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sources) { source in
                        sourceRow(source)
                            .contextMenu {
                                SourceContextMenu(
                                    source: source,
                                    canEject: store.canEjectSource(source),
                                    isEjecting: store.ejectingSourceID == source.id,
                                    onEject: {
                                        Task {
                                            await store.ejectSource(source)
                                        }
                                    }
                                )
                            }
                            .tag(source.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var sourceSelection: Binding<String?> {
        Binding(
            get: { store.selectedSource?.id },
            set: { selectedID in
                guard
                    let selectedID,
                    let source = store.sources.first(where: { $0.id == selectedID })
                else {
                    return
                }

                store.loadSource(source)
            }
        )
    }

    @ViewBuilder
    private func sourceRow(_ source: SourceDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: source))
                .foregroundStyle(iconColor(for: source))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .lineLimit(1)

                Text(source.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconName(for source: SourceDevice) -> String {
        switch source.kind {
        case .mountedVolume:
            return "externaldrive.fill"
        case .imageCaptureDevice:
            return "camera.fill"
        case .folderBookmark:
            return "folder.fill"
        }
    }

    private func iconColor(for source: SourceDevice) -> Color {
        switch source.kind {
        case .mountedVolume:
            return .blue
        case .imageCaptureDevice:
            return .orange
        case .folderBookmark:
            return .teal
        }
    }
}

private struct SourceContextMenu: View {
    let source: SourceDevice
    let canEject: Bool
    let isEjecting: Bool
    let onEject: () -> Void

    var body: some View {
        if source.kind == .mountedVolume {
            Button(action: onEject) {
                Label(isEjecting ? "Ejecting..." : "Eject", systemImage: "eject")
            }
            .disabled(!canEject)
        }
    }
}
