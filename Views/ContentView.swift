import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    @State private var didPerformInitialRefresh = false
    @State private var tableSelection: Set<String> = []
    @State private var inspectedUnknownFolderID: String?
    @State private var isInspectorPresented = true
    @State private var showingOverwriteConfirmation = false
    @State private var importAllRequested = false
    @State private var showingDeleteConfirmation = false
    @State private var showingClearSidecarConfirmation = false
    @State private var showingCaptureSourceDeletionConfirmation = false
    @State private var captureIDsPendingSourceDeletion: Set<String> = []

    private var inspectedCapture: LogicalCapture? {
        guard !tableSelection.isEmpty else {
            return nil
        }

        return tableSelection.lazy.compactMap(store.capture(withID:)).first
    }

    private var inspectedUnknownFolder: UnknownFolder? {
        guard let inspectedUnknownFolderID else {
            return nil
        }

        return store.unknownFolders.first { $0.id == inspectedUnknownFolderID }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                onRefresh: { refreshSources() },
                onAddFolder: chooseSourceFolder
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                CaptureListView(
                    store: store,
                    tableSelection: $tableSelection,
                    inspectedUnknownFolderID: $inspectedUnknownFolderID,
                    fileActions: .live,
                    onDeleteCapturesFromSource: { captureIDs in
                        captureIDsPendingSourceDeletion = captureIDs
                        showingCaptureSourceDeletionConfirmation = true
                    },
                    onClearSidecars: {
                        showingClearSidecarConfirmation = true
                    }
                )

                Divider()

                DestinationToolbarView(
                    store: store,
                    onChooseDestination: chooseDestinationFolder,
                    onImportSelected: { beginImport(importAll: false) },
                    onImportAll: { beginImport(importAll: true) }
                )
            }
            .navigationTitle(store.selectedSource?.displayName ?? "AutoImport")
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(
                capture: inspectedCapture,
                duplicateState: inspectedCapture.map(store.duplicateState(for:)),
                unknownFolder: inspectedUnknownFolder,
                showHelperFiles: Binding(
                    get: { store.showHelperFiles },
                    set: { store.showHelperFiles = $0 }
                )
            )
            .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .toolbar {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
        .task {
            guard !didPerformInitialRefresh else {
                return
            }

            didPerformInitialRefresh = true
            guard !isRunningTests else {
                return
            }
            refreshSources(preferNewDetectedMedia: true)
        }
        .mountedMediaNotifications(
            isEnabled: !isRunningTests,
            onMount: { refreshSources(preferNewDetectedMedia: true) },
            onUnmount: { refreshSources() }
        )
        .onChange(of: store.captureIDs) { _, captureIDs in
            let validIDs = Set(captureIDs)
            tableSelection = tableSelection.intersection(validIDs)

            if tableSelection.isEmpty, let firstID = captureIDs.first {
                tableSelection = [firstID]
                inspectedUnknownFolderID = nil
            }
        }
        .onChange(of: store.pendingDeletionCaptureIDs) { _, pendingDeletionCaptureIDs in
            showingDeleteConfirmation = !pendingDeletionCaptureIDs.isEmpty
        }
        .contentWorkflowAlerts(
            store: store,
            showingOverwriteConfirmation: $showingOverwriteConfirmation,
            importAllRequested: $importAllRequested,
            showingDeleteConfirmation: $showingDeleteConfirmation,
            showingClearSidecarConfirmation: $showingClearSidecarConfirmation,
            showingCaptureSourceDeletionConfirmation: $showingCaptureSourceDeletionConfirmation,
            captureIDsPendingSourceDeletion: $captureIDsPendingSourceDeletion
        )
    }

    private func refreshSources(preferNewDetectedMedia: Bool = false) {
        store.refreshSourcesAndLoadPreferredSource(
            preferNewDetectedMedia: preferNewDetectedMedia
        )
    }

    private func beginImport(importAll: Bool) {
        if importAll {
            store.selectAllCaptures()
        }

        store.refreshDestinationAvailability()
        guard store.canImportSelection else {
            return
        }

        importAllRequested = importAll

        if !store.duplicateCapturesInSelection.isEmpty {
            showingOverwriteConfirmation = true
        } else {
            Task {
                await store.importSelectedCaptures(overwriteDuplicates: false)
            }
        }
    }

    private func chooseSourceFolder() {
        guard let folderURL = pickFolder(title: "Choose Source Folder", prompt: "Add Source") else {
            return
        }

        store.addFolderSource(folderURL)
        tableSelection = []
        inspectedUnknownFolderID = nil
    }

    private func chooseDestinationFolder() {
        guard let folderURL = pickFolder(title: "Choose Import Destination", prompt: "Choose Destination") else {
            return
        }

        store.destinationURL = folderURL
    }

    private func pickFolder(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

#Preview {
    ContentView(store: AppStore())
}

private struct MountedMediaNotificationsModifier: ViewModifier {
    let isEnabled: Bool
    let onMount: @MainActor () -> Void
    let onUnmount: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                guard isEnabled else {
                    return
                }

                for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didMountNotification) {
                    await MainActor.run {
                        onMount()
                    }
                }
            }
            .task {
                guard isEnabled else {
                    return
                }

                for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didUnmountNotification) {
                    await MainActor.run {
                        onUnmount()
                    }
                }
            }
    }
}

private struct ContentWorkflowAlertsModifier: ViewModifier {
    let store: AppStore
    @Binding var showingOverwriteConfirmation: Bool
    @Binding var importAllRequested: Bool
    @Binding var showingDeleteConfirmation: Bool
    @Binding var showingClearSidecarConfirmation: Bool
    @Binding var showingCaptureSourceDeletionConfirmation: Bool
    @Binding var captureIDsPendingSourceDeletion: Set<String>

    func body(content: Content) -> some View {
        content
            .alert("Overwrite existing imports?", isPresented: $showingOverwriteConfirmation) {
                Button("Cancel", role: .cancel) {
                    importAllRequested = false
                }
                Button("Overwrite") {
                    if importAllRequested {
                        store.selectAllCaptures()
                    }

                    store.refreshDestinationAvailability()
                    guard store.canImportSelection else {
                        importAllRequested = false
                        return
                    }

                    Task {
                        await store.importSelectedCaptures(overwriteDuplicates: true)
                    }
                    importAllRequested = false
                }
                .disabled(!store.canImportSelection)
            } message: {
                Text("Some selected captures are already present in the destination. Overwriting will replace the existing files.")
            }
            .alert("Delete imported files from source?", isPresented: $showingDeleteConfirmation) {
                Button("Keep Files", role: .cancel) {
                    store.dismissPendingDeletion()
                }
                Button("Delete") {
                    Task {
                        await store.deleteImportedCapturesFromSource()
                    }
                }
            } message: {
                Text("Only captures that imported successfully will be removed from the source.")
            }
            .alert("Clear sidecar files?", isPresented: $showingClearSidecarConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear sidecar files", role: .destructive) {
                    Task {
                        await store.clearSidecarFilesFromSelectedSource()
                    }
                }
            } message: {
                Text(clearSidecarConfirmationMessage)
            }
            .alert(deleteCaptureConfirmationTitle, isPresented: $showingCaptureSourceDeletionConfirmation) {
                Button("Cancel", role: .cancel) {
                    captureIDsPendingSourceDeletion = []
                }
                Button(deleteCaptureConfirmationButtonTitle, role: .destructive) {
                    let captureIDs = captureIDsPendingSourceDeletion
                    guard !captureIDs.isEmpty else {
                        return
                    }

                    captureIDsPendingSourceDeletion = []
                    Task {
                        await store.deleteCapturesFromSource(ids: captureIDs)
                    }
                }
            } message: {
                Text(deleteCaptureConfirmationMessage)
            }
            .alert("Could not eject source", isPresented: sourceEjectionErrorPresented) {
                Button("OK") {
                    store.dismissSourceEjectionError()
                }
            } message: {
                Text(store.sourceEjectionErrorMessage ?? "The source could not be ejected.")
            }
    }

    private var clearSidecarConfirmationMessage: String {
        let count = store.sidecarFilesInSelectedSource.count
        let fileLabel = count == 1 ? "file" : "files"
        let sourceName = store.selectedSource?.displayName ?? "the selected source"
        return "This will delete \(count) sidecar \(fileLabel) from \(sourceName). Photos, videos, and unknown file types will be kept."
    }

    private var deleteCaptureConfirmationMessage: String {
        let captures = capturesPendingSourceDeletion
        let fileCount = captures.reduce(0) { $0 + $1.memberFiles.count }
        let fileLabel = fileCount == 1 ? "file" : "files"
        let sourceDeletionWarning = "Files are moved to Trash when possible; on removable media that does not support Trash, deletion may be permanent."

        if captures.count == 1 {
            let captureName = captures.first?.displayName ?? "this capture"
            return "This will delete \(captureName) and its \(fileCount) source \(fileLabel). \(sourceDeletionWarning)"
        }

        return "This will delete \(captures.count) captures and their \(fileCount) source \(fileLabel). \(sourceDeletionWarning)"
    }

    private var deleteCaptureConfirmationTitle: String {
        capturesPendingSourceDeletion.count == 1 ? "Delete capture from source?" : "Delete captures from source?"
    }

    private var deleteCaptureConfirmationButtonTitle: String {
        capturesPendingSourceDeletion.count == 1 ? "Delete Capture" : "Delete Captures"
    }

    private var capturesPendingSourceDeletion: [LogicalCapture] {
        store.captures.filter { captureIDsPendingSourceDeletion.contains($0.id) }
    }

    private var sourceEjectionErrorPresented: Binding<Bool> {
        Binding(
            get: { store.sourceEjectionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissSourceEjectionError()
                }
            }
        )
    }
}

private extension View {
    func contentWorkflowAlerts(
        store: AppStore,
        showingOverwriteConfirmation: Binding<Bool>,
        importAllRequested: Binding<Bool>,
        showingDeleteConfirmation: Binding<Bool>,
        showingClearSidecarConfirmation: Binding<Bool>,
        showingCaptureSourceDeletionConfirmation: Binding<Bool>,
        captureIDsPendingSourceDeletion: Binding<Set<String>>
    ) -> some View {
        modifier(
            ContentWorkflowAlertsModifier(
                store: store,
                showingOverwriteConfirmation: showingOverwriteConfirmation,
                importAllRequested: importAllRequested,
                showingDeleteConfirmation: showingDeleteConfirmation,
                showingClearSidecarConfirmation: showingClearSidecarConfirmation,
                showingCaptureSourceDeletionConfirmation: showingCaptureSourceDeletionConfirmation,
                captureIDsPendingSourceDeletion: captureIDsPendingSourceDeletion
            )
        )
    }

    func mountedMediaNotifications(
        isEnabled: Bool,
        onMount: @escaping @MainActor () -> Void,
        onUnmount: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(
            MountedMediaNotificationsModifier(
                isEnabled: isEnabled,
                onMount: onMount,
                onUnmount: onUnmount
            )
        )
    }
}
