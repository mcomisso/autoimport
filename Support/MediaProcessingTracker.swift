import Foundation
import Observation
import SwiftUI

struct MediaProcessingActivityID: Hashable, Sendable {
    fileprivate let rawValue: UUID
}

enum MediaProcessingActivityKind: Hashable, Sendable {
    case thumbnail
    case videoFrame
    case videoPreview

    var statusText: String {
        switch self {
        case .thumbnail:
            return "Processing thumbnail"
        case .videoFrame:
            return "Processing video"
        case .videoPreview:
            return "Preparing video"
        }
    }

    var detailVerb: String {
        switch self {
        case .thumbnail:
            return "Generating thumbnail"
        case .videoFrame:
            return "Generating video frame"
        case .videoPreview:
            return "Preparing video preview"
        }
    }

    var isVideoWork: Bool {
        switch self {
        case .thumbnail:
            return false
        case .videoFrame, .videoPreview:
            return true
        }
    }
}

private struct MediaProcessingActivity: Sendable {
    let kind: MediaProcessingActivityKind
    let fileName: String?
}

private struct MediaProcessingSummary: Equatable, Sendable {
    static let inactive = MediaProcessingSummary(
        activeActivityCount: 0,
        toolbarStatusText: "",
        detailText: "No background media processing",
        accessibilityText: "No background media processing"
    )

    let activeActivityCount: Int
    let toolbarStatusText: String
    let detailText: String
    let accessibilityText: String
}

@MainActor
@Observable
final class MediaProcessingTracker: @unchecked Sendable {
    @ObservationIgnored
    private var activeActivities: [MediaProcessingActivityID: MediaProcessingActivity] = [:]

    @ObservationIgnored
    private var videoWorkCount = 0

    @ObservationIgnored
    private var thumbnailWorkCount = 0

    private var summary = MediaProcessingSummary.inactive

    var activeActivityCount: Int {
        summary.activeActivityCount
    }

    var toolbarStatusText: String {
        summary.toolbarStatusText
    }

    var detailText: String {
        summary.detailText
    }

    var accessibilityText: String {
        summary.accessibilityText
    }

    var hasActiveWork: Bool {
        summary.activeActivityCount > 0
    }

    @discardableResult
    func begin(
        kind: MediaProcessingActivityKind,
        fileName: String?
    ) -> MediaProcessingActivityID {
        let id = MediaProcessingActivityID(rawValue: UUID())
        activeActivities[id] = MediaProcessingActivity(
            kind: kind,
            fileName: fileName
        )
        incrementCount(for: kind)
        refreshSummary()
        return id
    }

    func finish(_ id: MediaProcessingActivityID?) {
        guard let id, let activity = activeActivities.removeValue(forKey: id) else {
            return
        }

        decrementCount(for: activity.kind)
        refreshSummary()
    }

    private func incrementCount(for kind: MediaProcessingActivityKind) {
        if kind.isVideoWork {
            videoWorkCount += 1
        } else {
            thumbnailWorkCount += 1
        }
    }

    private func decrementCount(for kind: MediaProcessingActivityKind) {
        if kind.isVideoWork {
            videoWorkCount -= 1
        } else {
            thumbnailWorkCount -= 1
        }
    }

    private func refreshSummary() {
        let activeActivityCount = activeActivities.count

        guard activeActivityCount > 0 else {
            applySummary(.inactive)
            return
        }

        if activeActivityCount == 1, let activity = activeActivities.values.first {
            let detailText = activity.fileName.map { "\(activity.kind.detailVerb): \($0)" }
                ?? activity.kind.detailVerb
            applySummary(MediaProcessingSummary(
                activeActivityCount: activeActivityCount,
                toolbarStatusText: activity.kind.statusText,
                detailText: detailText,
                accessibilityText: detailText
            ))
            return
        }

        let detailText: String
        if videoWorkCount == 0 {
            detailText = "Processing \(activeActivityCount) thumbnails in the background"
        } else if thumbnailWorkCount == 0 {
            detailText = "Processing \(videoWorkCount) video tasks in the background"
        } else {
            detailText = "Processing \(videoWorkCount) video task\(videoWorkCount == 1 ? "" : "s") and \(thumbnailWorkCount) thumbnail task\(thumbnailWorkCount == 1 ? "" : "s") in the background"
        }
        applySummary(MediaProcessingSummary(
            activeActivityCount: activeActivityCount,
            toolbarStatusText: "\(activeActivityCount) media tasks",
            detailText: detailText,
            accessibilityText: detailText
        ))
    }

    private func applySummary(_ nextSummary: MediaProcessingSummary) {
        guard summary != nextSummary else {
            return
        }

        summary = nextSummary
    }
}

extension EnvironmentValues {
    @Entry var mediaProcessingTracker: MediaProcessingTracker? = nil
}
