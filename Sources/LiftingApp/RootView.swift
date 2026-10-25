import SwiftUI
import LiftingCore

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    var resolved: Palette { Palette(colors: store.data.settings.colors ?? ColorTheme(), dark: scheme == .dark, setTypes: store.data.customSetTypes) }
    @State private var selected = ProcessInfo.processInfo.arguments.contains("--progress") ? 2 : 0
    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                // Only Train pushes values onto a path; other tabs get a fresh one.
                NavigationStack(path: selected == 0 ? $store.trainPath : .constant(NavigationPath())) {
                    switch selected {
                    case 1: HistoryView()
                    case 2: ProgressView()
                    case 3: SettingsView()
                    default: TrainView()
                    }
                }.id([selected, store.trainRevision])
                ResumeBar(accessory: false)
                Divider()
                HStack(spacing: 0) {
                    navigationTab("Train", symbol: "dumbbell", index: 0)
                    navigationTab("History", symbol: "calendar", index: 1)
                    navigationTab("Progress", symbol: "chart.xyaxis.line", index: 2)
                    navigationTab("Settings", symbol: "gearshape", index: 3)
                }.padding(.vertical, 6).background(resolved.card)
            }
            #else
            tabs
            #endif
        }
        .tint(resolved.action)
        .preferredColorScheme(store.data.settings.theme == "system" ? nil : store.data.settings.theme == "dark" ? .dark : .light)
        .modifier(WorkoutPresentation())
        .alert("Could not complete action", isPresented: Binding(get: { store.error != nil && !store.workoutPresented }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.trainRevision) { selected = 0 }
        .environment(\.palette, resolved)
    }
    #if os(iOS)
    var showResume: Bool { store.data.activeSession != nil && !store.workoutPresented }
    @ViewBuilder var tabs: some View {
        let view = TabView(selection: $selected) {
            tab(0, "Train", "dumbbell", id: store.trainRevision, path: $store.trainPath) { TrainView() }
            tab(1, "History", "calendar") { HistoryView() }
            tab(2, "Progress", "chart.xyaxis.line") { ProgressView() }
            tab(3, "Settings", "gearshape") { SettingsView() }
        }
        if #available(iOS 26.1, *) {
            // Active workout lives in the system accessory slot above the tab bar, like a mini player.
            view.tabViewBottomAccessory(isEnabled: showResume) { ResumeBar(accessory: true) }.tabBarMinimizeBehavior(.onScrollDown)
        } else { view }
    }
    @ViewBuilder func tab<Content: View>(_ tag: Int, _ title: String, _ symbol: String, id: Int = 0, path: Binding<NavigationPath> = .constant(NavigationPath()), @ViewBuilder content: () -> Content) -> some View {
        let stack = NavigationStack(path: path) { content() }.id(id)
        if #available(iOS 26.1, *) { stack.tabItem { Label(title, systemImage: symbol) }.tag(tag) }
        else { stack.safeAreaInset(edge: .bottom, spacing: 0) { ResumeBar(accessory: false) }.tabItem { Label(title, systemImage: symbol) }.tag(tag) }
    }
    #endif
    #if os(macOS)
    func navigationTab(_ title: String, symbol: String, index: Int) -> some View {
        Button { selected = index } label: {
            VStack(spacing: 4) { Image(systemName: symbol).font(.title3); Text(title).font(.caption) }.frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(selected == index ? resolved.action : Color.secondary).accessibilityAddTraits(selected == index ? .isSelected : []).accessibilityIdentifier("tab.\(title)")
    }
    #endif
}

/// The active workout, shown above the tab bar while the workout screen is minimized.
struct ResumeBar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    /// True when the system draws the container (the iOS tab bar accessory).
    var accessory: Bool
    var body: some View {
        if let session = store.data.activeSession, !store.workoutPresented {
            Button { store.workoutPresented = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional").font(.body.weight(.semibold)).foregroundStyle(palette.action)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.data.title(for: session)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(session.pausedAt != nil ? "Paused · " : WorkoutReminder.isOverdue(session, at: context.date) ? "Still running · " : "")\(clockText(session.duration(at: context.date)))  \(session.completedSets) of \(session.totalSets) sets").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, accessory ? 16 : 18).padding(.vertical, accessory ? 0 : 10)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .modifier(LegacyResumeBackground(enabled: !accessory))
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).buttonStyle(.plain).accessibilityLabel("Resume \(session.name)").accessibilityIdentifier("workout.resume")
        }
    }
}

private struct LegacyResumeBackground: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.floatingCapsule().padding(.horizontal, 12).padding(.bottom, 6) } else { content }
    }
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
