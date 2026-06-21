import SwiftUI

struct CaptureRowView: View {
    let row: CaptureRowPresentation
    let selection: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: selection)
            .toggleStyle(.checkbox)
            .labelsHidden()

            CaptureThumbnailView(
                thumbnailFileURL: row.thumbnailFileURL,
                previewFileURL: row.previewFileURL
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let status = CaptureDisplayFormatter.duplicateStatus(row.duplicateState) {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(row.duplicateState == .duplicate ? .orange : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quinary, in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    ForEach(row.detailTexts, id: \.self) { detailText in
                        Text(detailText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .opacity(row.duplicateState == .duplicate ? 0.46 : 1)
    }
}
