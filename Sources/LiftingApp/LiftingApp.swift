import SwiftUI
import LiftingCore

@main
struct TorqueApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup("Torque") {
            RootView().environmentObject(store)
                #if os(macOS)
                .frame(minWidth: 360, idealWidth: 440, minHeight: 600, idealHeight: 840)
                #endif
                .task { store.prepareNotifications(); await store.startHealth() }
                .task { await store.runSyncLoop() }
                .onChange(of: phase) { _, value in if value == .active { Task { await store.syncNow(); await store.refreshHealth() } } }
        }
        #if os(macOS)
        .defaultSize(width: 440, height: 840)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
