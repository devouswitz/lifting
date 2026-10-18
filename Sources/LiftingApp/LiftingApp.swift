import SwiftUI
import LiftingCore

@main
struct LiftingApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .frame(minWidth: 360, idealWidth: 440, minHeight: 600, idealHeight: 840)
        }
        #if os(macOS)
        .defaultSize(width: 440, height: 840)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
