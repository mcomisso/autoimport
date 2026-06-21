import SwiftUI

struct CheckForUpdatesCommand: View {
    @ObservedObject var softwareUpdates: SoftwareUpdateController

    var body: some View {
        Button("Check for Updates...") {
            softwareUpdates.checkForUpdates()
        }
        .disabled(!softwareUpdates.canCheckForUpdates)
    }
}
