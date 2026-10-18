import SwiftUI
import LiftingCore

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State private var selected = ProcessInfo.processInfo.arguments.contains("--progress") ? 2 : 0
    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                NavigationStack {
                    switch selected {
                    case 1: HistoryView()
                    case 2: ProgressView()
                    case 3: SettingsView()
                    default: TrainView()
                    }
                }.id(selected)
                Divider()
                HStack(spacing: 0) {
                    navigationTab("Train", symbol: "dumbbell", index: 0)
                    navigationTab("History", symbol: "calendar", index: 1)
                    navigationTab("Progress", symbol: "chart.xyaxis.line", index: 2)
                    navigationTab("Settings", symbol: "gearshape", index: 3)
                }.padding(.vertical, 6).background(Palette.surface(scheme))
            }
            #else
            TabView(selection: $selected) {
            NavigationStack { TrainView() }.tabItem { Label("Train", systemImage: "dumbbell") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "calendar") }.tag(1)
            NavigationStack { ProgressView() }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
            }
            #endif
        }
        .tint(Palette.tint(scheme))
        .preferredColorScheme(store.data.settings.theme == "system" ? nil : store.data.settings.theme == "dark" ? .dark : .light)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let session = store.data.activeSession, !store.workoutPresented {
                Button { store.workoutPresented = true } label: {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text(session.name).fontWeight(.semibold)
                        Spacer()
                        Text("\(session.completedSets)/\(session.totalSets) sets").font(.subheadline)
                        Image(systemName: "chevron.up")
                    }.padding().background(Palette.surface(scheme))
                }.buttonStyle(.plain).accessibilityIdentifier("workout.resume")
            }
        }
        .modifier(WorkoutPresentation())
        .alert("Could not complete action", isPresented: Binding(get: { store.error != nil && !store.workoutPresented }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    #if os(macOS)
    func navigationTab(_ title: String, symbol: String, index: Int) -> some View {
        Button { selected = index } label: {
            VStack(spacing: 4) { Image(systemName: symbol).font(.title3); Text(title).font(.caption) }.frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(selected == index ? Palette.tint(scheme) : Color.secondary).accessibilityAddTraits(selected == index ? .isSelected : []).accessibilityIdentifier("tab.\(title)")
    }
    #endif
}

struct WorkoutPresentation: ViewModifier {
    @EnvironmentObject var store: AppStore
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $store.workoutPresented) { WorkoutView().environmentObject(store) }
        #else
        content.sheet(isPresented: $store.workoutPresented) { WorkoutView().environmentObject(store).frame(minWidth: 420, minHeight: 720) }
        #endif
    }
}
