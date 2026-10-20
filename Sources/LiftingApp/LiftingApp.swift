import SwiftUI
import LiftingCore

@main
struct LiftingApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .frame(minWidth: 360, idealWidth: 440, minHeight: 600, idealHeight: 840)
                .task { await store.startHealth() }
                .task { await store.runSyncLoop() }
                .onChange(of: phase) { _, value in if value == .active { Task { await store.syncNow(); await store.refreshHealth() } } }
        }
        #if os(macOS)
        .defaultSize(width: 440, height: 840)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
