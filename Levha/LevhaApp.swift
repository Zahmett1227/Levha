import SwiftUI
import SwiftData

@main
struct LevhaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Bicim.tr)
        }
        .modelContainer(Depo.container)
    }
}
