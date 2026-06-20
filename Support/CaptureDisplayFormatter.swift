import Foundation

enum CaptureDisplayFormatter {
    static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
        }

        return "\(minutes):" + String(format: "%02d", seconds)
    }

    static func multipartSummary(segmentCount: Int, totalDuration: TimeInterval?) -> String? {
        guard segmentCount > 1 else {
            return nil
        }

        if let totalDuration {
            return "\(segmentCount) parts · \(duration(totalDuration))"
        }

        return "\(segmentCount) parts"
    }

    static func fileSize(_ byteCount: Int64) -> String {
        byteCountFormatterLock.lock()
        defer {
            byteCountFormatterLock.unlock()
        }

        return byteCountFormatter.string(fromByteCount: byteCount)
    }

    static func dimensions(_ pixelSize: PixelSize?) -> String? {
        guard let pixelSize else {
            return nil
        }

        return "\(pixelSize.width)×\(pixelSize.height)"
    }

    static func duplicateStatus(_ state: CaptureDuplicateState) -> String? {
        switch state {
        case .unique:
            return nil
        case .partial:
            return "Partial duplicate"
        case .duplicate:
            return "Already imported"
        }
    }

    static func timestamp(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static let byteCountFormatterLock = NSLock()

    nonisolated(unsafe) private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }()
}
