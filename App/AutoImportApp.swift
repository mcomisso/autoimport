import SwiftUI

@main
struct AutoImportApp: App {
    @State private var store = AppStore()
    @StateObject private var softwareUpdates = SoftwareUpdateController()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 1180, height: 820)
        .defaultWindowPlacement { content, context in
            let idealSize = content.sizeThatFits(.unspecified)
            let visibleSize = context.defaultDisplay.visibleRect.size
            let width = min(max(idealSize.width, 920), visibleSize.width * 0.92)
            let height = min(max(idealSize.height, 640), visibleSize.height * 0.9)

            return WindowPlacement(size: CGSize(width: width, height: height))
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(softwareUpdates: softwareUpdates)
            }
        }
    }
}
