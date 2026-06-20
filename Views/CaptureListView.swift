import SwiftUI

struct CaptureListView: View {
    @Bindable var store: AppStore
    @Binding var tableSelection: Set<String>
    @Binding var inspectedUnknownFolderID: String?
    let fileActions: CaptureFileActions
    let onDeleteCapturesFromSource: (Set<String>) -> Void
    let onClearSidecars: () -> Void

    @State private var sortOrder: [KeyPathComparator<CaptureRowPresentation>] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.captures.isEmpty {
                ContentUnavailableView(
                    "No captures found",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(emptyStateMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CaptureTableView(
                    store: store,
                    rows: sortedCaptureRows,
                    tableSelection: $tableSelection,
                    inspectedUnknownFolderID: $inspectedUnknownFolderID,
                    fileActions: fileActions,
                    onDeleteCapturesFromSource: onDeleteCapturesFromSource,
                    sortOrder: $sortOrder
                )
            }

            if store.showUnknownFolders {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Unknown Folders")
                            .font(.headline)

                        Spacer()

                        Text("\(store.visibleUnknownFolders.count)")
                            .foregroundStyle(.secondary)
                    }

                    if store.visibleUnknownFolders.isEmpty {
                        Text("No unknown folders in this source.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(store.visibleUnknownFolders) { unknownFolder in
                                    Button {
                                        inspectedUnknownFolderID = unknownFolder.id
                                        tableSelection = []
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder")
                                                .foregroundStyle(.secondary)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(unknownFolder.relativeFolderPath.isEmpty ? "Root" : unknownFolder.relativeFolderPath)
                                                    .lineLimit(1)

                                                Text("\(unknownFolder.files.count) files")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(
                                                    inspectedUnknownFolderID == unknownFolder.id
                                                        ? AnyShapeStyle(.quaternary)
                                                        : AnyShapeStyle(.clear)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 150)
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedSource?.displayName ?? "Library")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(headerSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let importSummary = store.importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quinary, in: Capsule())
            }

            Button(role: .destructive) {
                onClearSidecars()
            } label: {
                Label("Clear sidecar files", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!store.canClearSidecarFiles)
            .help(clearSidecarHelp)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var sortedCaptureRows: [CaptureRowPresentation] {
        guard !sortOrder.isEmpty else {
            return store.captureRows
        }

        return store.captureRows.sorted(using: sortOrder + [KeyPathComparator(\.captureSortValue)])
    }

    private var headerSubtitle: String {
        let selectedCount = store.selectedCaptureIDs.count
        let captureCount = store.captures.count
        let suffix = selectedCount == 1 ? "marked" : "marked"
        return "\(captureCount) captures · \(selectedCount) \(suffix) for import"
    }

    private var emptyStateMessage: String {
        if store.selectedSource?.kind == .imageCaptureDevice {
            return "This device is visible through Image Capture but does not expose a browsable mounted volume yet."
        }

        return "Connect a camera or add a source folder to scan for media."
    }

    private var clearSidecarHelp: String {
        let count = store.sidecarFilesInSelectedSource.count
        guard count > 0 else {
            return "No sidecar files found in this source"
        }

        let fileLabel = count == 1 ? "file" : "files"
        return "Delete \(count) sidecar \(fileLabel) from the selected source"
    }
}

private struct CaptureTableView: View {
    @Bindable var store: AppStore
    let rows: [CaptureRowPresentation]
    @Binding var tableSelection: Set<String>
    @Binding var inspectedUnknownFolderID: String?
    let fileActions: CaptureFileActions
    let onDeleteCapturesFromSource: (Set<String>) -> Void
    @Binding var sortOrder: [KeyPathComparator<CaptureRowPresentation>]

    var body: some View {
        Table(of: CaptureRowPresentation.self, selection: $tableSelection, sortOrder: $sortOrder) {
            TableColumn("Capture", value: \.captureSortValue) { item in
                CaptureRowView(
                    row: item,
                    selection: Binding(
                        get: { store.isCaptureSelected(id: item.id) },
                        set: { isSelected in
                            store.setCaptureSelected(id: item.id, isSelected: isSelected)
                        }
                    )
                )
            }
            .width(min: 360, ideal: 420)

            TableColumn("Kind", value: \.kindSortValue) { item in
                Text(item.kindText)
                    .opacity(item.isDuplicate ? 0.46 : 1)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Date", value: \.modificationDateSortValue) { item in
                Text(item.timestampText)
                    .foregroundStyle(.secondary)
                    .opacity(item.isDuplicate ? 0.46 : 1)
            }
            .width(min: 140, ideal: 180)

            TableColumn("Size", value: \.sizeSortValue) { item in
                Text(item.sizeText)
                    .opacity(item.isDuplicate ? 0.46 : 1)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Status", value: \.statusSortValue) { item in
                Text(item.statusText)
                    .foregroundStyle(.secondary)
                    .opacity(item.isDuplicate ? 0.46 : 1)
            }
            .width(min: 110, ideal: 150)
        } rows: {
            ForEach(rows) { item in
                TableRow(item)
                    .contextMenu {
                        let deletionIDs = deletionIDs(for: item)

                        CaptureContextMenu(
                            row: item,
                            isMarkedForImport: store.isCaptureSelected(id: item.id),
                            deleteSelectionCount: deletionIDs.count,
                            onOpen: {
                                fileActions.open(item.capture)
                            },
                            onRevealInFinder: {
                                fileActions.revealInFinder(item.capture)
                            },
                            onCopyFilePath: {
                                fileActions.copyFilePath(item.capture)
                            },
                            onToggleImportMark: {
                                store.setCaptureSelected(
                                    id: item.id,
                                    isSelected: !store.isCaptureSelected(id: item.id)
                                )
                            },
                            onInspect: {
                                tableSelection = [item.id]
                                inspectedUnknownFolderID = nil
                            },
                            onDeleteFromSource: {
                                guard !deletionIDs.isEmpty else {
                                    return
                                }

                                tableSelection = deletionIDs
                                inspectedUnknownFolderID = nil
                                onDeleteCapturesFromSource(deletionIDs)
                            }
                        )
                    }
            }
        }
        .onChange(of: tableSelection) { _, newSelection in
            if !newSelection.isEmpty {
                inspectedUnknownFolderID = nil
            }
        }
        .onKeyPress(.space) {
            guard !tableSelection.isEmpty else { return .ignored }
            store.toggleMarks(for: tableSelection)
            return .handled
        }
        .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            tableSelection = Set(store.captureIDs)
            return .handled
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deletionIDs(for item: CaptureRowPresentation) -> Set<String> {
        let candidateIDs: Set<String> = tableSelection.contains(item.id) ? tableSelection : [item.id]
        return Set(candidateIDs.filter(store.canDeleteCaptureFromSource(id:)))
    }
}

private struct CaptureContextMenu: View {
    let row: CaptureRowPresentation
    let isMarkedForImport: Bool
    let deleteSelectionCount: Int
    let onOpen: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyFilePath: () -> Void
    let onToggleImportMark: () -> Void
    let onInspect: () -> Void
    let onDeleteFromSource: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        .disabled(row.capture.fileActionURL == nil)

        Button(action: onRevealInFinder) {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .disabled(row.capture.finderSelectionURLs.isEmpty)

        Button(action: onCopyFilePath) {
            Label("Copy File Path", systemImage: "doc.on.doc")
        }
        .disabled(row.capture.fileActionURL == nil)

        Divider()

        Button(action: onToggleImportMark) {
            Label(
                isMarkedForImport ? "Unmark for Import" : "Mark for Import",
                systemImage: isMarkedForImport ? "minus.square" : "checkmark.square"
            )
        }

        Button(action: onInspect) {
            Label("Show in Inspector", systemImage: "sidebar.trailing")
        }

        Divider()

        Button(role: .destructive, action: onDeleteFromSource) {
            Label(deleteActionTitle, systemImage: "trash")
        }
        .disabled(deleteSelectionCount == 0)
    }

    private var deleteActionTitle: String {
        guard deleteSelectionCount > 1 else {
            return "Delete from Source..."
        }

        return "Delete \(deleteSelectionCount) Captures from Source..."
    }
}
