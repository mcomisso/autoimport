import SwiftUI

struct ImportPreviewView: View {
    let plan: ImportPlan
    let onImport: () -> Void

    private var skippedCount: Int {
        plan.captures.count(where: \.skipsDuplicate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Preview")
                .font(.title2.weight(.semibold))

            Text("\(plan.captures.count - skippedCount) to import, \(skippedCount) duplicates to skip · \(CaptureDisplayFormatter.fileSize(plan.totalBytes))")
                .foregroundStyle(.secondary)

            List {
                ForEach(plan.captures, id: \.capture.id) { plannedCapture in
                    DisclosureGroup {
                        if plannedCapture.skipsDuplicate {
                            Text("Already imported")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(plannedCapture.files, id: \.source.id) { file in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.source.fileName)
                                    Text("\(actionText(file.action)) · \(file.destinationURL.path(percentEncoded: false))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(plannedCapture.capture.displayName)
                            Spacer()
                            Text(plannedCapture.skipsDuplicate ? "Skip" : "Import")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("The destination is checked again when import starts. Changes since this preview may change the result.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") {
                    onImportDone()
                }
                Button(skippedCount > 0 ? "Import and Skip Duplicates" : "Import Selected", action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
    }

    @Environment(\.dismiss) private var dismiss

    private func onImportDone() {
        dismiss()
    }

    private func actionText(_ action: PlannedFileImport.Action) -> String {
        switch action {
        case .copy: "Copy"
        case .rename: "Rename"
        case .replace: "Replace"
        }
    }
}
