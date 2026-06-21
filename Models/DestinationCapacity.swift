import Foundation

enum DestinationAvailability: Equatable, Sendable {
    case notSelected
    case checking
    case reachable
    case unavailable

    var isReachable: Bool {
        self == .reachable
    }

    static func resolve(url: URL) -> DestinationAvailability {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false

        guard
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            (try? url.checkResourceIsReachable()) == true
        else {
            return .unavailable
        }

        return .reachable
    }
}

struct DestinationCapacity: Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    static func measure(at url: URL) -> DestinationCapacity? {
        let baseKeys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]

        guard let baseValues = try? url.resourceValues(forKeys: baseKeys) else {
            return nil
        }

        guard let total = baseValues.volumeTotalCapacity else {
            return nil
        }

        let totalBytes = Int64(total)
        if let rawAvailable = baseValues.volumeAvailableCapacity.map({ Int64($0) }),
           rawAvailable > 0 {
            return DestinationCapacity(
                totalBytes: totalBytes,
                availableBytes: min(totalBytes, rawAvailable)
            )
        }

        let scopedKeys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
        ]
        let scopedValues = try? url.resourceValues(forKeys: scopedKeys)

        guard let available = resolveAvailableBytes(
            totalBytes: totalBytes,
            importantUsageCapacity: scopedValues?.volumeAvailableCapacityForImportantUsage,
            opportunisticUsageCapacity: scopedValues?.volumeAvailableCapacityForOpportunisticUsage,
            rawAvailableCapacity: baseValues.volumeAvailableCapacity.map { Int64($0) }
        ) else {
            return nil
        }

        return DestinationCapacity(
            totalBytes: totalBytes,
            availableBytes: available
        )
    }

    static func resolveAvailableBytes(
        totalBytes: Int64,
        importantUsageCapacity: Int64?,
        opportunisticUsageCapacity: Int64?,
        rawAvailableCapacity: Int64?
    ) -> Int64? {
        guard totalBytes >= 0 else {
            return nil
        }

        // External filesystems can report zero for usage-scoped values while Finder shows the raw free space.
        let candidates = [
            importantUsageCapacity,
            opportunisticUsageCapacity,
            rawAvailableCapacity,
        ]
        .compactMap { $0 }
        .filter { $0 >= 0 }

        guard let available = candidates.max() else {
            return nil
        }

        return min(totalBytes, available)
    }
}
