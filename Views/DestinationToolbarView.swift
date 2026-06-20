import SwiftUI

struct DestinationToolbarView: View {
    @Bindable var store: AppStore
    let onChooseDestination: () -> Void
    let onImportSelected: () -> Void
    let onImportAll: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let progress = store.importProgress, store.isImporting {
                progressBanner(progress)
            }

            if let capacity = store.destinationCapacity {
                DestinationCapacityChart(
                    capacity: capacity,
                    incomingBytes: store.selectedCapturesTotalSize
                )
            }

            mainRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }

    private var mainRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import To")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onChooseDestination) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(destinationIconColor)

                        Text(store.destinationURL?.path(percentEncoded: false) ?? "Choose destination")
                            .lineLimit(1)
                            .foregroundStyle(destinationTextColor)
                            .frame(maxWidth: 360, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Picker("Organize", selection: $store.organizationMode) {
                Text("Flat").tag(DestinationOrganizationMode.flat)
                Text("By Date").tag(DestinationOrganizationMode.byDate)
                Text("Camera / Date").tag(DestinationOrganizationMode.byCameraAndDate)
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Toggle("Unknown Folders", isOn: $store.showUnknownFolders)
                .toggleStyle(.switch)
                .frame(width: 170)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(markedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        store.selectAllCaptures()
                    } label: {
                        Label("Select All", systemImage: "checkmark.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!store.canSelectAllCaptures)

                    Button {
                        store.clearCaptureSelection()
                    } label: {
                        Label("Deselect All", systemImage: "square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!store.canDeselectAllCaptures)

                    Button {
                        onImportAll()
                    } label: {
                        Label("Import All", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!store.canImportAllCaptures)

                    Button {
                        onImportSelected()
                    } label: {
                        HStack(spacing: 8) {
                            if store.isImporting {
                                ProgressView()
                                    .controlSize(.small)
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(store.isImporting ? "Importing…" : "Import Selected")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canImportSelection)
                }
            }
        }
    }

    @ViewBuilder
    private func progressBanner(_ progress: ImportProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView(value: progress.fractionComplete)
                    .progressViewStyle(.linear)

                Text("\(Int(progress.fractionComplete * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("\(progress.completedCaptures) / \(progress.totalCaptures)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(CaptureDisplayFormatter.fileSize(progress.completedBytes)) of \(CaptureDisplayFormatter.fileSize(progress.totalBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let name = progress.currentCaptureName {
                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
        }
    }

    private var markedSummary: String {
        let count = store.selectedCaptureIDs.count
        guard count > 0 else {
            return "No captures marked"
        }

        let sizeText = CaptureDisplayFormatter.fileSize(store.selectedCapturesTotalSize)
        return "\(count) captures marked · \(sizeText)"
    }

    private var destinationIconColor: Color {
        store.destinationAvailability == .unavailable ? .red : .blue
    }

    private var destinationTextColor: Color {
        store.destinationAvailability == .unavailable ? .red : .primary
    }

}
