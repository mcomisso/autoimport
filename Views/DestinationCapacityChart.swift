import SwiftUI

struct DestinationCapacityChart: View {
    let capacity: DestinationCapacity
    let incomingBytes: Int64

    private var incomingClamped: Int64 {
        min(incomingBytes, capacity.availableBytes)
    }

    private var overflowBytes: Int64 {
        max(0, incomingBytes - capacity.availableBytes)
    }

    private var remainingAfterImport: Int64 {
        max(0, capacity.availableBytes - incomingClamped)
    }

    private var fits: Bool {
        overflowBytes == 0
    }

    private var displayTotal: Int64 {
        max(capacity.totalBytes, capacity.usedBytes + incomingBytes)
    }

    private var segments: [Segment] {
        [
            Segment(kind: .used, bytes: capacity.usedBytes),
            Segment(kind: .incoming, bytes: incomingClamped),
            Segment(kind: .free, bytes: remainingAfterImport),
            Segment(kind: .over, bytes: overflowBytes),
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Destination capacity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Text(headlineText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(fits ? Color.secondary : Color.red.opacity(0.85))
            }

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        segment.kind.fill
                            .frame(width: width(for: segment.bytes, in: geometry.size.width))
                    }
                }
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .frame(height: 12)

            HStack(spacing: 16) {
                ForEach(SegmentKind.allCases) { kind in
                    LegendChip(kind: kind, bytes: bytes(for: kind))
                }
                Spacer()
            }
        }
    }

    private func width(for bytes: Int64, in totalWidth: CGFloat) -> CGFloat {
        guard displayTotal > 0 else { return 0 }
        return totalWidth * CGFloat(bytes) / CGFloat(displayTotal)
    }

    private func bytes(for kind: SegmentKind) -> Int64 {
        switch kind {
        case .used: return capacity.usedBytes
        case .incoming: return incomingBytes
        case .free: return remainingAfterImport
        case .over: return overflowBytes
        }
    }

    private var headlineText: String {
        let available = CaptureDisplayFormatter.fileSize(capacity.availableBytes)
        let total = CaptureDisplayFormatter.fileSize(capacity.totalBytes)
        let required = CaptureDisplayFormatter.fileSize(incomingBytes)

        if fits {
            return "\(required) needed  ·  \(available) free of \(total)"
        }

        let shortfall = CaptureDisplayFormatter.fileSize(overflowBytes)
        return "\(required) needed  ·  exceeds free by \(shortfall)"
    }
}

private struct Segment: Identifiable {
    let kind: SegmentKind
    let bytes: Int64
    var id: SegmentKind { kind }
}

private enum SegmentKind: String, CaseIterable, Identifiable {
    case used
    case incoming
    case free
    case over

    var id: String { rawValue }

    var label: String {
        switch self {
        case .used: return "Used"
        case .incoming: return "Incoming"
        case .free: return "Free after"
        case .over: return "Over"
        }
    }

    @ViewBuilder
    var fill: some View {
        switch self {
        case .used:
            Rectangle()
                .fill(Color.primary.opacity(0.16))
        case .incoming:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.95),
                            Color.accentColor.opacity(0.70),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .free:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.55),
                            Color.green.opacity(0.32),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .over:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.85),
                            Color.red.opacity(0.65),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    var swatchGradient: LinearGradient {
        switch self {
        case .used:
            return LinearGradient(
                colors: [Color.primary.opacity(0.20), Color.primary.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .incoming:
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .free:
            return LinearGradient(
                colors: [Color.green.opacity(0.55), Color.green.opacity(0.32)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .over:
            return LinearGradient(
                colors: [Color.red.opacity(0.85), Color.red.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct LegendChip: View {
    let kind: SegmentKind
    let bytes: Int64

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(kind.swatchGradient)
                .frame(width: 10, height: 10)

            Text(kind.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(CaptureDisplayFormatter.fileSize(bytes))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }
}
