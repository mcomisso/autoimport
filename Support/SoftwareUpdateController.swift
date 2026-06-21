import Combine
import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        guard Self.hasRequiredConfiguration(in: bundle) else {
            updaterController = nil
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
        canCheckForUpdates = updaterController?.updater.canCheckForUpdates ?? false
    }

    private static func hasRequiredConfiguration(in bundle: Bundle) -> Bool {
        guard
            let feedURLString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feedURLString),
            ["https", "http"].contains(feedURL.scheme?.lowercased()),
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        return true
    }
}
