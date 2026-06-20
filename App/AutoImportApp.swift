import SwiftUI

@main
struct AutoImportApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 1480, height: 960)
    }
}
