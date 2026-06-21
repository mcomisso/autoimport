import SwiftUI

struct DestinationToolbarView: View {
    @Bindable var store: AppStore
    let onChooseDestination: () -> Void
    let onImportSelected: () -> Void
    let onImportAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DestinationToolbarStatusSection(store: store)

            DestinationToolbarControls(
                store: store,
                onChooseDestination: onChooseDestination,
                onImportSelected: onImportSelected,
                onImportAll: onImportAll
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.thinMaterial)
    }
}

private struct DestinationToolbarStatusSection: View {
    let store: AppStore

    var body: some View {
        let progress = store.importProgress
        let isImporting = store.isImporting
        let capacity = store.destinationCapacity
        let hasStatus = (progress != nil && isImporting) || capacity != nil

        VStack(spacing: 12) {
            if let progress, isImporting {
                DestinationImportProgressBanner(progress: progress)
            }

            if let capacity {
                DestinationCapacityChart(
                    capacity: capacity,
                    incomingBytes: store.selectedCapturesTotalSize
                )
            }
        }
        .padding(.bottom, hasStatus ? 12 : 0)
    }
}

private struct DestinationImportProgressBanner: View {
    let progress: ImportProgress

    var body: some View {
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
}

private struct DestinationToolbarControls: View {
    @Bindable var store: AppStore
    let onChooseDestination: () -> Void
    let onImportSelected: () -> Void
    let onImportAll: () -> Void

    var body: some View {
        mainRow
    }

    private var mainRow: some View {
        ViewThatFits(in: .horizontal) {
            expandedMainRow
            compactMainRows
        }
    }

    private var expandedMainRow: some View {
        HStack(spacing: 14) {
            destinationControl(maxWidth: 360)

            organizationControls

            Spacer()

            actionGroup(alignment: .trailing)
        }
    }

    private var compactMainRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    destinationControl(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    organizationControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    destinationControl(maxWidth: .infinity)
                    organizationControls
                }
            }

            actionGroup(alignment: .leading)
        }
    }

    private func destinationControl(maxWidth: CGFloat?) -> some View {
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
                        .truncationMode(.middle)
                        .foregroundStyle(destinationTextColor)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 180, maxWidth: maxWidth, alignment: .leading)
    }

    private var organizationControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                organizationPicker
                unknownFoldersToggle
                AutomaticImportToggle(isOn: $store.automaticallyImportDetectedMedia)
            }

            VStack(alignment: .leading, spacing: 8) {
                organizationPicker

                HStack(spacing: 12) {
                    unknownFoldersToggle
                    AutomaticImportToggle(isOn: $store.automaticallyImportDetectedMedia)
                }
            }
        }
    }

    private var organizationPicker: some View {
        Picker("Organize", selection: $store.organizationMode) {
            Text("Flat").tag(DestinationOrganizationMode.flat)
            Text("By Date").tag(DestinationOrganizationMode.byDate)
            Text("Camera / Date").tag(DestinationOrganizationMode.byCameraAndDate)
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }

    private var unknownFoldersToggle: some View {
        Toggle("Unknown Folders", isOn: $store.showUnknownFolders)
            .toggleStyle(.switch)
            .frame(width: 170)
    }

    private func actionGroup(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(markedSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            actionButtons
        }
    }

    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                selectAllButton
                deselectAllButton
                importAllButton
                importSelectedButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    selectAllButton
                    deselectAllButton
                }

                HStack(spacing: 10) {
                    importAllButton
                    importSelectedButton
                }
            }
        }
    }

    private var selectAllButton: some View {
        Button {
            store.selectAllCaptures()
        } label: {
            Label("Select All", systemImage: "checkmark.square")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!store.canSelectAllCaptures)
    }

    private var deselectAllButton: some View {
        Button {
            store.clearCaptureSelection()
        } label: {
            Label("Deselect All", systemImage: "square")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!store.canDeselectAllCaptures)
    }

    private var importAllButton: some View {
        Button {
            onImportAll()
        } label: {
            Label("Import All", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!store.canImportAllCaptures)
    }

    private var importSelectedButton: some View {
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

    private var markedSummary: String {
        let count = store.selectedCaptureCount
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

private struct AutomaticImportToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Auto Import", isOn: $isOn)
            .toggleStyle(.switch)
            .frame(width: 145)
            .help("Automatically import new mounted media when it is detected.")
    }
}
