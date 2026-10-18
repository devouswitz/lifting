import SwiftUI
import LiftingCore

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State private var selected = ProcessInfo.processInfo.arguments.contains("--progress") ? 2 : 0
    var body: some View {
        TabView(selection: $selected) {
            NavigationStack { TrainView() }.tabItem { Label("Train", systemImage: "dumbbell") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "calendar") }.tag(1)
            NavigationStack { ProgressView() }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
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

struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State private var newRoutine = false
    @State private var name = ""
    var next: Routine? {
        guard !store.data.routines.isEmpty else { return nil }
        if let last = store.data.sessions.last?.routineID, let index = store.data.routines.firstIndex(where: { $0.id == last }) { return store.data.routines[(index + 1) % store.data.routines.count] }
        return store.data.routines.first
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.demo { Chip(title: "Demo data") }
                if store.storageBlocked { Text("Local data needs recovery. Open Settings to import a backup.").foregroundStyle(.red) }
                if store.data.activeSession == nil, let next {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("NEXT WORKOUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) { Text(next.name).font(.largeTitle.bold()); Spacer(); Text("\(next.slots.count) exercises").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(next.slots.prefix(4)) { slot in
                            if let variant = store.data.variant(slot.variantID), let exercise = store.data.exercise(variant.exerciseID) {
                                HStack { Text(exercise.name); Spacer(); Text(counted(variant.sets.filter { $0.kind != .warmup }.count, "set")).foregroundStyle(.secondary).font(.subheadline) }
                            }
                        }
                        Button { store.start(next) } label: { Label("Start workout", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(AccentButtonStyle()).accessibilityIdentifier("train.start")
                    }.card()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Routines").font(.title2.weight(.semibold)); Spacer(); Button { newRoutine = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Create routine") }
                    if store.data.routines.isEmpty { EmptyState(symbol: "list.bullet.rectangle", text: "No routines yet.") }
                    ForEach(store.data.routines) { routine in
                        HStack(spacing: 12) {
                            NavigationLink { RoutineEditor(routineID: routine.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(routine.name).font(.headline)
                                    Text("\(routine.slots.count) exercises").font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if store.data.activeSession == nil { Button { store.start(routine) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }.buttonStyle(.bordered).accessibilityLabel("Start \(routine.name)") }
                        }.card()
                    }
                }
                if store.data.activeSession == nil { Button("Start empty workout", action: store.emptyWorkout).buttonStyle(.bordered).frame(maxWidth: .infinity) }
            }.padding(16)
        }
        .background(Palette.background(scheme)).navigationTitle("Train")
        .alert("New routine", isPresented: $newRoutine) {
            TextField("Name", text: $name)
            Button("Create") { let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); if !clean.isEmpty { store.perform { $0.routines.append(Routine(name: clean)) }; name = "" } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
