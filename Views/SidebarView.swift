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
                Section("Connected Sources") {
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

                Section("Remembered Volumes") {
                    if store.knownVolumes.isEmpty {
                        Text("Connect a volume to set its import behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.knownVolumes) { volume in
                            KnownVolumeRow(
                                volume: volume,
                                onChange: { enabled in
                                    store.setAutomaticImportEnabled(enabled, forVolumeID: volume.id)
                                }
                            )
                        }
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

private struct KnownVolumeRow: View {
    let volume: KnownVolume
    let onChange: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)

                Text(volume.displayName)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Toggle("Auto Import", isOn: Binding(
                    get: { volume.automaticImportEnabled },
                    set: onChange
                ))
                .labelsHidden()
                .accessibilityLabel("Automatically import \(volume.displayName) on the next mount")
            }

            if volume.automaticImportEnabled {
                Text("Imports automatically on next mount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Manual import on next mount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
