import SwiftUI
import Signet

@main
struct ShelfseerApp: App {
    var body: some Scene {
        WindowGroup("shelfseer") {
            ContentView()
                .cverTheme(ReefTheme())
                .preferredColorScheme(.dark)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
