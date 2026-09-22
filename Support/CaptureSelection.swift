import Foundation

/// Keeps capture selection order, membership, and totals together.
struct CaptureSelection: Sendable {
    struct Summary: Equatable, Sendable {
        var count = 0
        var totalSize: Int64 = 0
        var duplicateCount = 0
        var partialDuplicateCount = 0
    }

    private(set) var ids: [String] = []
    private(set) var idSet: Set<String> = []
    private(set) var summary = Summary()

    private var sizesByID: [String: Int64] = [:]
    private var duplicateStatesByID: [String: CaptureDuplicateState] = [:]

    mutating func updateCaptures(_ captures: [LogicalCapture]) {
        sizesByID = Dictionary(captures.map { ($0.id, $0.totalSize) }, uniquingKeysWith: { first, _ in first })
        replace(ids)
    }

    mutating func updateDuplicateStates(_ states: [String: CaptureDuplicateState]) {
        duplicateStatesByID = states
        summary = summarize(ids)
    }

    mutating func replace(_ requestedIDs: [String]) {
        var seen = Set<String>()
        ids = requestedIDs.filter { sizesByID[$0] != nil && seen.insert($0).inserted }
        idSet = seen
        summary = summarize(ids)
    }

    mutating func setSelected(_ id: String, isSelected: Bool) {
        if isSelected {
            guard sizesByID[id] != nil, idSet.insert(id).inserted else { return }
            ids.append(id)
            add(id)
        } else {
            guard idSet.remove(id) != nil else { return }
            ids.removeAll { $0 == id }
            remove(id)
        }
    }

    mutating func toggleMarks(_ requestedIDs: Set<String>, inCaptureOrder captureIDs: [String]) {
        guard !requestedIDs.isEmpty else { return }

        if requestedIDs.isSubset(of: idSet) {
            let removedIDs = ids.filter { requestedIDs.contains($0) }
            ids.removeAll { requestedIDs.contains($0) }
            for id in removedIDs {
                idSet.remove(id)
                remove(id)
            }
        } else {
            for id in captureIDs where requestedIDs.contains(id) && sizesByID[id] != nil {
                guard idSet.insert(id).inserted else { continue }
                ids.append(id)
                add(id)
            }
        }
    }

    private func summarize(_ ids: [String]) -> Summary {
        var result = Summary()
        for id in ids {
            result.count += 1
            result.totalSize += sizesByID[id] ?? 0
            switch duplicateStatesByID[id] ?? .unique {
            case .duplicate: result.duplicateCount += 1
            case .partial: result.partialDuplicateCount += 1
            case .unique: break
            }
        }
        return result
    }

    private mutating func add(_ id: String) {
        summary.count += 1
        summary.totalSize += sizesByID[id] ?? 0
        switch duplicateStatesByID[id] ?? .unique {
        case .duplicate: summary.duplicateCount += 1
        case .partial: summary.partialDuplicateCount += 1
        case .unique: break
        }
    }

    private mutating func remove(_ id: String) {
        summary.count -= 1
        summary.totalSize -= sizesByID[id] ?? 0
        switch duplicateStatesByID[id] ?? .unique {
        case .duplicate: summary.duplicateCount -= 1
        case .partial: summary.partialDuplicateCount -= 1
        case .unique: break
        }
    }
}
