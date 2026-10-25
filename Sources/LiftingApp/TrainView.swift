import SwiftUI
import LiftingCore

/// What to train today: the loaded program's next day, the rest of its days, and an empty workout.
struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let program = store.data.activeProgram {
                    programRow(program)
                    if let next = program.nextDayID.flatMap(store.data.routine) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Next workout")
                            NextDayCard(day: next, program: program)
                        }
                    }
                    let later = laterDays(program)
                    if !later.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Later in \(program.name)")
                            DayList(days: later, program: program, showsMenu: true)
                        }
                    }
                    if program.dayIDs.isEmpty {
                        NavigationLink { ProgramEditor(programID: program.id) } label: { Label("Add a Day to \(program.name)", systemImage: "plus") }.buttonStyle(FieldButtonStyle())
                    }
                } else {
                    noProgram
                }
                Button { store.emptyWorkout() } label: { Label("Start Empty Workout", systemImage: "plus") }
                    .buttonStyle(FieldButtonStyle()).disabled(store.data.activeSession != nil).accessibilityIdentifier("train.empty")
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .background(palette.background)
        .navigationTitle("Train")
        .navigationDestination(for: DayRoute.self) { RoutineEditor(routineID: $0.id, showsStart: true) }
    }

    private func programRow(_ program: TrainingProgram) -> some View {
        NavigationLink { ProgramsView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.on(.action))
                    .frame(width: 34, height: 34).background(palette.action, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(program.name).font(.headline).foregroundStyle(.primary)
                    Text(counted(program.dayIDs.count, "day")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !typeSize.isAccessibilitySize { Text("Programs").font(.subheadline).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).card(padding: 12).accessibilityLabel("Programs, \(program.name), \(counted(program.dayIDs.count, "day"))").accessibilityIdentifier("train.program")
    }

    private var noProgram: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 34, weight: .medium)).foregroundStyle(.tertiary)
            Text("No program loaded").font(.headline)
            NavigationLink { ProgramsView() } label: { Text("Choose a Program").frame(maxWidth: 260) }.buttonStyle(AccentButtonStyle())
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    /// Days after the next one, in the order they come up.
    private func laterDays(_ program: TrainingProgram) -> [Routine] {
        store.data.upcomingDays(program.id).dropFirst().compactMap(store.data.routine)
    }
}

/// A day opened from Train. A fixed ID, so an open day never turns into another when the next day changes,
/// and a value the Train path can clear when a workout ends.
struct DayRoute: Hashable { let id: UUID }

/// The program's next day: its exercises with targets and working weights, and the Start control.
struct NextDayCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    let day: Routine
    let program: TrainingProgram
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                NavigationLink(value: DayRoute(id: day.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name).font(.title2.weight(.bold)).foregroundStyle(.primary)
                        if let index = program.dayIDs.firstIndex(of: day.id) { Text("Day \(index + 1) of \(program.dayIDs.count)").font(.subheadline).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                DayMenu(day: day, program: program)
            }
            if !day.slots.isEmpty { ExerciseTargets(day: day) }
            StartDayButton(day: day)
        }.card(padding: 16)
    }
}

/// Exercise rows with set × rep targets and working weight.
struct ExerciseTargets: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    let day: Routine
    /// Adds a line naming warm-ups and techniques under each exercise.
    var detailed = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(day.slots.enumerated()), id: \.element.id) { index, slot in
                if let variant = store.data.variant(slot.variantID), let exercise = store.data.exercise(variant.exerciseID) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name).font(.body).lineLimit(1)
                            details(variant: variant, slot: slot)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(target(variant)).font(.figure(15, weight: .regular)).foregroundStyle(.secondary)
                        Text(exercise.mode == .strength ? weightSummary(zip(variant.sets, variant.resolvedWeights).compactMap { $0.kind == .warmup ? nil : $1 }, unit: store.data.settings.unit) : "")
                            .font(.figure(15)).frame(minWidth: 64, alignment: .trailing)
                    }.padding(.vertical, 9)
                    if index < day.slots.count - 1 { Divider() }
                }
            }
        }
    }
    @ViewBuilder func details(variant: Variant, slot: RoutineSlot) -> some View {
        let group = slot.group.isEmpty ? 0 : day.slots.filter { $0.group == slot.group }.count
        let warmups = detailed ? variant.sets.filter { $0.kind == .warmup }.count : 0
        let technique = !detailed ? nil : variant.sets.contains { $0.kind == .drop } ? "Drop sets" : variant.sets.contains { $0.kind == .myoActivation || $0.kind == .myoMini } ? "MYO" : nil
        if group > 1 || warmups > 0 || technique != nil {
            HStack(spacing: 10) {
                if warmups > 0 { Text(counted(warmups, "warm-up")).foregroundStyle(palette.warmup) }
                if let technique { Text(technique).foregroundStyle(palette.technique) }
                if group > 1 { Label(group > 2 ? "Circuit" : "Superset", systemImage: "link").foregroundStyle(palette.technique) }
            }.font(.caption.weight(.medium))
        }
    }
    func target(_ variant: Variant) -> String {
        let work = prescribedWork(variant.sets)
        guard let plan = work.first else { return "" }
        if let seconds = plan.seconds { return clockText(seconds) }
        if let reps = plan.reps { return "\(work.count) × \(reps)\(plan.repCeiling.map { $0 != reps ? "–\($0)" : "" } ?? "")" }
        return counted(work.count, "set")
    }
}

/// Start, Resume, or add exercises, depending on the day and any active workout.
struct StartDayButton: View {
    @EnvironmentObject var store: AppStore
    let day: Routine
    @State private var adding = false
    var body: some View {
        if day.slots.isEmpty {
            Button { adding = true } label: { Label("Add Exercises", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(AccentButtonStyle())
                .sheet(isPresented: $adding) { ExercisePicker(title: "Add Exercises", onAdd: { store.add($0, to: day.id) }).sheetSize() }
        } else if let session = store.data.activeSession {
            Button { store.workoutPresented = true } label: { Text(session.routineID == day.id ? "Resume Workout" : "Resume \(session.name)").frame(maxWidth: .infinity) }
                .buttonStyle(AccentButtonStyle()).accessibilityIdentifier("train.resume")
        } else {
            Button { store.start(day) } label: { Text("Start Workout").frame(maxWidth: .infinity) }.buttonStyle(AccentButtonStyle()).accessibilityIdentifier("train.start")
        }
    }
}

/// Grouped rows that open each day.
struct DayList: View {
    @EnvironmentObject var store: AppStore
    let days: [Routine]
    let program: TrainingProgram?
    /// Shows each day's action menu in place of the disclosure chevron.
    var showsMenu = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    NavigationLink(value: DayRoute(id: day.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(day.name).font(.headline).foregroundStyle(.primary)
                                Text(day.slots.isEmpty ? "No exercises yet" : day.slots.compactMap { store.data.variant($0.variantID).flatMap { store.data.exercise($0.exerciseID)?.name } }.joined(separator: ", "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if !showsMenu { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("train.day.\(day.id)")
                    if showsMenu { DayMenu(day: day, program: program) }
                }.padding(.leading, 16).padding(.trailing, showsMenu ? 8 : 16)
                if index < days.count - 1 { Divider().padding(.leading, 16) }
            }
        }.card(padding: 0)
    }
}

/// Every action for a day or template, in one menu.
struct DayMenu: View {
    @EnvironmentObject var store: AppStore
    let day: Routine
    let program: TrainingProgram?
    var onDelete: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onWarmups: (() -> Void)? = nil
    @State private var export: CSVExportRequest?
    @State private var deleting = false
    @State private var skipping = false
    /// Position in the upcoming order, where 0 is the next workout.
    private var place: Int? { program.flatMap { store.data.upcomingDays($0.id).firstIndex(of: day.id) } }
    private var isNext: Bool { program?.id == store.data.activeProgramID && place == 0 }
    var body: some View {
        Menu {
            if let onRename { Button("Rename Day", systemImage: "pencil", action: onRename) }
            if let onWarmups { Button("Warm-ups for Day", systemImage: "flame", action: onWarmups).disabled(day.slots.isEmpty) }
            if let program {
                if isNext {
                    Button("Skip Workout", systemImage: "forward") { skipping = true }.disabled(store.data.activeSession?.routineID == day.id)
                } else {
                    Button("Make Next Workout", systemImage: "arrow.right.circle") { store.perform { try $0.selectNextDay(day.id, in: program.id); if $0.activeProgramID != program.id { try $0.loadProgram(program.id) } } }
                }
                Divider()
                Button("Duplicate Day", systemImage: "plus.square.on.square") { store.perform { _ = try $0.addDay(to: program.id, templateID: day.id, name: TrainingData.uniqueName(day.name + " copy", among: store.data.routines.map(\.name))) } }
                Button("Save Day Copy", systemImage: "square.and.arrow.down.on.square") { store.perform { _ = try $0.saveDayAsTemplate(day.id) } }
            } else {
                if !store.data.programs.isEmpty {
                    Menu { ForEach(store.data.programs) { target in Button(target.name) { store.perform { _ = try $0.addDay(to: target.id, templateID: day.id) } } } } label: { Label("Add to Program", systemImage: "plus.rectangle.on.rectangle") }
                }
                Button("Duplicate Saved Day", systemImage: "plus.square.on.square") { store.perform { _ = try $0.saveDayAsTemplate(day.id, name: TrainingData.uniqueName(day.name + " copy", among: store.data.dayTemplates.map(\.name))) } }
            }
            Button("Export CSV", systemImage: "square.and.arrow.up") { do { export = try .day(day.id, in: store.data) } catch { store.error = error.localizedDescription } }
            Divider()
            Button(program == nil ? "Delete Template" : "Delete Day", systemImage: "trash", role: .destructive) { deleting = true }
        } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .compactMenu().fixedSize().foregroundStyle(.secondary).accessibilityLabel("Options for \(day.name)")
        .confirmationDialog(program == nil ? "Delete this template?" : "Delete this day?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if store.perform({ $0.removeDay(day.id) }) { onDelete?() } }
        } message: { Text("Workout history is kept.") }
        .confirmationDialog("Skip \(day.name)?", isPresented: $skipping, titleVisibility: .visible) {
            Button("Skip Workout") { if let program { store.skipNext(in: program.id) } }
        } message: { Text(skipMessage) }
        .modifier(CSVExportModifier(request: $export))
    }
    private var skipMessage: String {
        let following = program.flatMap { store.data.upcomingDays($0.id).dropFirst().first.flatMap(store.data.routine) }
        let next = following.map { " \($0.name) becomes the next workout." } ?? ""
        return "It's saved to History with every set marked skipped.\(next)"
    }
}
