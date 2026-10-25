import SwiftUI
import LiftingCore
#if os(iOS)
import UIKit
#endif

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.palette) var palette
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lifted: LiftedRow?
    @State private var rows = RowFrames()
    @State private var adding = false
    @State private var finishing = false
    @State private var discard = false
    @State private var cancelling = false
    @State private var sessionNotes = false
    @State private var warmups = false
    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                if let session = store.data.activeSession {
                    LazyVStack(spacing: 12) {
                        WorkoutSummaryHeader(session: session)
                        if session.pausedAt != nil {
                            Button { store.pauseWorkout(false) } label: { Label("Resume Workout", systemImage: "play.fill") }.buttonStyle(AccentButtonStyle()).accessibilityIdentifier("workout.unpause")
                        }
                        ForEach(session.exercises) { exercise in WorkoutExerciseCard(exerciseID: exercise.id, reordering: reordering).id(exercise.id) }
                        Button { adding = true } label: { Label("Add Exercise", systemImage: "plus") }.buttonStyle(FieldButtonStyle()).padding(.top, 4)
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                    .reorderingStack("workout")
                }
            }.reorderingScroll().background(palette.background)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.autoFocusRevision) { _, _ in
                guard let id = store.autoFocusedExerciseID else { return }
                if reduceMotion { reader.scrollTo(id, anchor: .top) }
                else { withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(id, anchor: .top) } }
            }
            }
            .navigationTitle(store.data.activeSession?.name ?? "Workout").inlineTitle()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) { minimizeButton }
                ToolbarItem(placement: .primaryAction) { workoutMenu }
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
                ToolbarItem(placement: .primaryAction) { finishButton }
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    RestBar().animation(.snappy, value: store.data.restDeadline)
                    #if os(macOS)
                    HStack { minimizeButton; workoutMenu; Spacer(); finishButton }.padding(12).background(.bar)
                    #endif
                }
            }
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.fontWeight(.semibold)
                }
            }
            #endif
            .sheet(isPresented: $adding) { ExercisePicker(title: "Add Exercises", onAdd: { exercises in store.perform { data in for exercise in exercises { try data.addExerciseToSession(exercise.id) } } }).environmentObject(store).sheetSize() }
            .sheet(isPresented: $warmups) { ApplyWarmupPreset().environmentObject(store).sheetSize() }
            .sheet(isPresented: $finishing) { finishSheet }
            .confirmationDialog("Cancel this workout?", isPresented: $cancelling, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { store.discard() }
                Button("Keep Workout", role: .cancel) {}
            } message: { Text("Logged sets in this workout will not be saved.") }
            .sheet(isPresented: $sessionNotes) {
                NavigationStack {
                    ThemedForm {
                        Section("Name") { SavedNameField(name: store.data.activeSession?.name ?? "") { value in store.editActive { $0.name = value } } }
                        Section("Note") { TextField("Workout note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(5...12) }
                    }.formStyle(.grouped).navigationTitle("Workout").inlineTitle()
                }.sheetSize()
            }
        }.tint(palette.action)
        .alert("Could not complete action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onAppear {
            store.requestWorkoutAlerts()
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = store.data.settings.keepAwake
            #endif
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }
    private var reordering: Reordering {
        Reordering(space: "workout", lifted: $lifted, rows: rows) { source, target, after in
            store.perform { $0.moveSessionExercise(source, relativeTo: target, after: after) }
        }
    }
    private var minimizeButton: some View {
        Button { store.workoutPresented = false } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Minimize workout")
    }
    private var workoutMenu: some View {
        Menu {
            Button(store.data.activeSession?.pausedAt == nil ? "Pause Workout" : "Resume Workout", systemImage: store.data.activeSession?.pausedAt == nil ? "pause" : "play") { store.pauseWorkout(store.data.activeSession?.pausedAt == nil) }
            Button("Name and Note", systemImage: "note.text") { sessionNotes = true }.accessibilityIdentifier("workout.note")
            Button("Warm-ups for Workout", systemImage: "flame") { warmups = true }
            Divider()
            Button("Collapse All", systemImage: "chevron.up") { store.perform { $0.setAllExercisesExpanded(false) } }.accessibilityIdentifier("workout.collapseAll")
            Button("Expand All", systemImage: "chevron.down") { store.perform { $0.setAllExercisesExpanded(true) } }.accessibilityIdentifier("workout.expandAll")
            Divider()
            Button("Cancel Workout", systemImage: "xmark", role: .destructive) { cancelling = true }.accessibilityIdentifier("workout.cancel")
        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Workout options").accessibilityIdentifier("workout.options")
    }
    private var finishButton: some View {
        Button("Finish") { finishing = true }.fontWeight(.semibold).primaryButtonStyle().accessibilityIdentifier("workout.finish")
    }
    var finishSheet: some View {
        NavigationStack {
            ThemedForm {
                if let session = store.data.activeSession {
                    Section {
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout())
                        layout {
                            MetricTile(value: "\(session.completedSets)", label: "Sets")
                            MetricTile(value: clockText(session.duration()), label: "Duration")
                            let volume = volumeText(session, settings: store.data.settings)
                            MetricTile(value: volume.total, label: volume.warmup.map { "Volume, \($0)" } ?? "Volume")
                        }.padding(.vertical, 4)
                    } footer: {
                        if session.completedSets == 0 { Text("Log at least one set to save this workout.") }
                        else if session.completedSets < session.totalSets { Text("\(counted(session.totalSets - session.completedSets, "unchecked set")) will be saved as skipped.") }
                    }
                    Section("Workout note") { TextField("Note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(3...6) }
                    Section {
                        Button { store.finish(); finishing = false } label: { Text("Save Workout").frame(maxWidth: .infinity, minHeight: 26) }.buttonStyle(AccentButtonStyle()).disabled(session.completedSets == 0).accessibilityIdentifier("workout.save")
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                    Section { Button("Discard Workout", role: .destructive) { discard = true }.frame(maxWidth: .infinity) }
                }
            }.formStyle(.grouped).navigationTitle("Finish Workout").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { finishing = false } }
            }
            .confirmationDialog("Discard this workout?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { finishing = false; store.discard() }
            } message: { Text("Logged sets in this workout will not be saved.") }
        }.sheetSize()
    }
}

/// Elapsed time, volume, and set progress for the active workout.
struct WorkoutSummaryHeader: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                TimelineView(.periodic(from: .now, by: 1)) { context in stat("Duration", clockText(session.duration(at: context.date))) }
                let volume = volumeText(session, settings: store.data.settings)
                stat("Volume", volume.total, note: volume.warmup)
                stat("Sets", "\(session.completedSets) of \(session.totalSets)")
            }
            CapsuleProgress(value: session.totalSets == 0 ? 0 : Double(session.completedSets) / Double(session.totalSets))
        }.padding(.horizontal, 4).padding(.bottom, 4)
    }
    func stat(_ title: String, _ value: String, note: String? = nil) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.figure(17)).lineLimit(1).minimumScaleFactor(0.8)
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).accessibilityElement(children: .combine)
    }
}

/// Icon and title with tighter spacing than the default label style.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 5) { configuration.icon.imageScale(.small); configuration.title } }
}

/// The rest timer above the bottom edge. When rest runs out it turns solid in the rest color, with one firm
/// vibration, and stays until skipped or the next set is logged.
struct RestBar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @State private var total: Double = 1
    @State private var done = false
    var body: some View {
        if let deadline = store.data.restDeadline {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = deadline.timeIntervalSince(context.date)
                let over = remaining <= 0
                let ink = over ? palette.on(.rest) : palette.rest
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(ink.opacity(0.25), lineWidth: 4)
                        Circle().trim(from: 0, to: over ? 1 : total > 0 ? remaining / total : 0).stroke(ink, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    }.frame(width: 30, height: 30).accessibilityHidden(true)
                    Text(over ? "Rest done" : clockText(remaining)).font(.figure(22, weight: .bold)).foregroundStyle(over ? palette.on(.rest) : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(over ? "Rest complete" : "Rest, \(clockText(remaining)) left")
                    let step = store.data.settings.restAdjustment
                    Group {
                        Button("−\(stepText(step))") { store.adjustRest(-Double(step)) }.accessibilityLabel("Subtract \(step) seconds")
                        Button("+\(stepText(step))") { store.adjustRest(Double(step)) }.accessibilityLabel("Add \(step) seconds")
                    }.font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 48, height: 36).background(ink.opacity(palette.dark || over ? 0.2 : 0.12), in: Capsule()).buttonStyle(.plain)
                    .contextMenu { RestStepPicker() }
                    Button(over ? "Done" : "Skip", action: store.skipRest).font(.subheadline.weight(.semibold)).foregroundStyle(over ? palette.rest : palette.on(.rest))
                        .frame(width: 56, height: 36).background(over ? palette.on(.rest) : palette.rest, in: Capsule()).buttonStyle(.plain).accessibilityIdentifier("rest.skip")
                }
                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
                .background(over ? palette.rest : palette.card, in: Capsule())
                .shadow(color: .black.opacity(palette.dark ? 0.5 : 0.12), radius: 16, y: 4)
                .padding(.horizontal, 12).padding(.bottom, 8)
                .animation(.snappy, value: over)
                .onChange(of: over) { _, value in done = value }
            }
            .sensoryFeedback(.warning, trigger: done) { old, new in !old && new && store.data.settings.haptics }
            .task(id: deadline) { total = max(1, deadline.timeIntervalSince(store.restStartedAt ?? Date())) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    private func stepText(_ seconds: Int) -> String { seconds % 60 == 0 ? "\(seconds / 60)m" : "\(seconds)" }
}

/// How much the rest timer's − and + buttons change it. Held on those buttons, and in Settings.
struct RestStepPicker: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    var tiled = false
    var body: some View {
        Picker(selection: Binding(get: { store.data.settings.restAdjustment }, set: { value in store.perform { $0.settings.restStep = value } })) {
            ForEach([5, 10, 15, 30, 60], id: \.self) { Text($0 < 60 ? "\($0) seconds" : "1 minute").tag($0) }
        } label: {
            if tiled { TileLabel(title: "Adjust Rest By", symbol: "plusminus", color: palette.rest) } else { Text("Adjust Rest By") }
        }
    }
}

/// Everything a live exercise card can present. One sheet at a time, owned by the card, so auto-collapse
/// waits while any of them is open and a row leaving the table never takes its keypad with it.
enum ExerciseSheet: Identifiable {
    case substitute, technique(Technique), savedPlan(UUID), plates, link, warmups, rest
    case keypad(NumericEdit), load(UUID), details(UUID), reps(UUID)
    var id: String {
        switch self {
        case .substitute: return "substitute"
        case .technique(let t): return "technique.\(t.rawValue)"
        case .savedPlan: return "saved"
        case .plates: return "plates"
        case .link: return "link"
        case .warmups: return "warmups"
        case .rest: return "rest"
        case .keypad(let edit): return "keypad.\(edit.id)"
        case .load(let id): return "load.\(id)"
        case .details(let id): return "details.\(id)"
        case .reps(let id): return "reps.\(id)"
        }
    }
}

struct WorkoutExerciseCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    let reordering: Reordering
    @State private var sheet: ExerciseSheet?
    @State private var removing = false
    @FocusState private var noteFocused: Bool
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        if let item {
            let exercises = store.data.activeSession?.exercises ?? []
            let done = item.sets.filter { $0.completedAt != nil }.count
            ExerciseCard(name: item.name, link: linkText, summary: compactSummary(item), expanded: item.collapsed != true,
                         toggle: { withAnimation(.snappy) { _ = store.perform { $0.setExerciseExpanded(exerciseID, expanded: item.collapsed == true, focus: item.collapsed == true) } } },
                         order: CardOrder(id: exerciseID, canMoveUp: exercises.first?.id != exerciseID, canMoveDown: exercises.last?.id != exerciseID, reordering: reordering) { offset in
                             store.perform { $0.moveSessionExercise(exerciseID, offset: offset) }
                         },
                         accessibilityValue: "\(item.collapsed == true ? "Collapsed" : "Expanded"), \(done) of \(item.sets.count) sets",
                         identifier: "workout.\(exerciseID)") {
                if completed { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.completed) }
                else { Text("\(done) of \(item.sets.count)").font(.figure(13, weight: .medium)).foregroundStyle(.secondary) }
            } menu: { menuItems(item) } content: {
                ExerciseInfoRow(exerciseID: item.exerciseID, swap: { id in store.perform { try $0.substitute(sessionExerciseID: exerciseID, with: id, future: false) } }, swapDisabled: completed,
                                load: loadSummary(item.sets.filter { $0.plan.kind != .warmup }.map(\.weight), mode: item.mode, unit: store.data.settings.unit), rest: item.restSeconds,
                                warmupRest: item.sets.contains { $0.plan.kind == .warmup } ? item.warmupRestSeconds ?? store.data.settings.warmupRestDefault : nil,
                                editRest: { sheet = .keypad(.rest(item.restSeconds, context: item.name) { seconds in editItem { $0.restSeconds = seconds } }) },
                                editWarmupRest: {
                                    sheet = .keypad(.rest(item.warmupRestSeconds ?? store.data.settings.warmupRestDefault, title: "Rest After Warm-ups", context: item.name) { seconds in editItem { $0.warmupRestSeconds = seconds } })
                                }, restSettings: { sheet = .rest })
                TextField("Add a note", text: Binding(get: { self.item?.notes ?? "" }, set: { value in store.editExercise(exerciseID) { $0.notes = value } }), axis: .vertical)
                    .font(.subheadline).lineLimit(1...5).foregroundStyle(.primary).focused($noteFocused).padding(.bottom, 4).accessibilityIdentifier("workout.\(exerciseID).noteField")
                if let from = item.substitutedFrom { Label("Instead of \(from)", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary) }
                if !item.recurringNotes.isEmpty { Label(item.recurringNotes, systemImage: "pin.fill").font(.footnote).foregroundStyle(.secondary) }
                if item.mode == .cardio || item.sets.contains(where: { $0.seconds != nil }) { CardioTimer(exerciseID: exerciseID) }
                if !item.sets.isEmpty { setTable(item) }
                ExerciseActions(addTitle: item.mode == .cardio ? "Add Interval" : item.sets.last?.plan.kind == .myoMini ? "Add Mini-set" : "Add Set",
                                quickAdds: item.mode != .cardio, adder: adder(item), customize: { sheet = .technique($0) }, identifier: "workout.\(exerciseID)")
            }
            .task(id: autoCollapseReady) {
                guard autoCollapseReady else { return }
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                store.collapseCompleted(exerciseID)
            }
            .sheet(item: $sheet) { sheetContent($0, item: item).environmentObject(store) }
            .confirmationDialog("Remove \(item.name)?", isPresented: $removing) { Button("Remove from workout", role: .destructive) { store.editActive { $0.exercises.removeAll { $0.id == exerciseID } } } } message: { Text("This removes its sets from the current workout.") }
        }
    }
    private func editItem(_ change: @escaping (inout SessionExercise) -> Void) -> Bool {
        store.perform { data in
            guard let index = data.activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw TrainingError.invalid("Exercise unavailable.") }
            change(&data.activeSession!.exercises[index])
        }
    }
    private var linkText: String? {
        guard let session = store.data.activeSession, let title = session.linkTitle(for: exerciseID) else { return nil }
        let partners = session.linkedExercises(for: exerciseID).filter { $0.id != exerciseID }.map(\.name).formatted(.list(type: .and))
        return "\(title) with \(partners)"
    }
    @ViewBuilder private func menuItems(_ item: SessionExercise) -> some View {
        Button("Swap Exercise", systemImage: "arrow.triangle.2.circlepath") { sheet = .substitute }.accessibilityIdentifier("workout.\(item.id).substitute")
        Button("Superset / Circuit", systemImage: "link") { sheet = .link }
        Divider()
        if let last = store.data.settings.lastWarmups, item.mode != .cardio {
            Button("Apply \(last.name)", systemImage: "flame.fill") { store.perform { try $0.applyWarmups(last.sets, toSessionExercises: [exerciseID]) } }
        }
        Button("Apply Warm-up Preset", systemImage: "flame") { sheet = .warmups }.disabled(item.mode == .cardio)
        Button("Edit Saved Prescription", systemImage: "slider.horizontal.3") { sheet = .savedPlan(item.variantID) }
        Button("Save Changes to Plan", systemImage: "square.and.arrow.down") { store.perform { try $0.saveSessionPlan(exerciseID) } }
        Button("Plate Calculator", systemImage: "circle.grid.2x1") { sheet = .plates }.disabled(item.mode != .strength)
        Divider()
        Button("Remove from Workout", systemImage: "trash", role: .destructive) { removing = true }
    }
    private func adder(_ item: SessionExercise) -> SetAdder {
        SetAdder(set: { store.perform { try $0.addSessionSet(to: exerciseID) } }, warmup: addWarmup,
                 typed: { kind, id in store.perform { try $0.addTypedSet(to: exerciseID, kind: kind, customTypeID: id) } },
                 technique: { technique in
                     let plans = store.data.techniqueDefaults(for: item.exerciseID).plans(technique)
                     if store.perform({ try $0.applyTechnique(to: exerciseID, plans: plans, isDrop: technique == .drop, replaceRemaining: false, saveFuture: false) }), technique == .drop { store.cancelRestAlert() }
                 })
    }
    @ViewBuilder private func sheetContent(_ sheet: ExerciseSheet, item: SessionExercise) -> some View {
        let unit = store.data.settings.unit
        let set = { (id: UUID) in item.sets.first { $0.id == id } }
        switch sheet {
        case .substitute:
            ExercisePicker(title: "Substitute", similarMuscle: store.data.exercise(item.exerciseID)?.muscle, substitution: true, onSubstitute: { exercise, future in
                store.perform { try $0.substitute(sessionExerciseID: exerciseID, with: exercise.id, future: future) }
            }).sheetSize()
        case .technique(let technique):
            TechniqueEditor(technique: technique, exerciseID: item.exerciseID, live: true) { plans, replace, future in
                let success = store.perform { try $0.applyTechnique(to: exerciseID, plans: plans, isDrop: technique == .drop, replaceRemaining: replace, saveFuture: future) }
                if success && technique == .drop { store.cancelRestAlert() }
                return success
            }.sheetSize()
        case .savedPlan(let id): SavedExerciseEditor(variantID: id).sheetSize()
        case .plates: PlateView(initialWeight: unit.display(item.sets.last?.weight ?? 0)).sheetSize()
        case .link: LinkedExerciseEditor(exerciseID: exerciseID).sheetSize()
        case .warmups: ApplyWarmupPreset(exerciseID: exerciseID).sheetSize()
        case .rest:
            RestSettingsEditor(name: item.name,
                               rest: Binding(get: { self.item?.restSeconds ?? 0 }, set: { value in _ = editItem { $0.restSeconds = value } }),
                               warmupRest: Binding(get: { self.item?.warmupRestSeconds }, set: { value in _ = editItem { $0.warmupRestSeconds = value } }),
                               failRest: Binding(get: { self.item?.failRestSeconds }, set: { value in _ = editItem { $0.failRestSeconds = value } }))
        case .keypad(let edit): NumberEditor(edit: edit)
        case .load(let id):
            if let plan = set(id)?.plan {
                LoadRuleEditor(plan: plan, unit: unit, suggestedWeight: set(id)?.weight, mode: item.mode) { plan in store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: id, plan: plan) } }
            }
        case .details(let id):
            if let plan = set(id)?.plan { LivePlanEditor(exerciseID: exerciseID, setID: id, initial: plan).sheetSize() }
        case .reps(let id):
            if let plan = set(id)?.plan {
                RepValuesEditor(plan: plan) { plan in store.perform { try $0.setRepTarget(plan, exerciseID: exerciseID, setID: id) } }
            }
        }
    }
    /// One column header for the exercise, then warm-ups and working sets under small group labels.
    func setTable(_ item: SessionExercise) -> some View {
        let columns = SetTableColumns(item: item)
        let warmups = Array(item.sets.enumerated()).filter { $0.element.plan.kind == .warmup }
        let work = Array(item.sets.enumerated()).filter { $0.element.plan.kind != .warmup }
        let unit = store.data.settings.unit.rawValue
        // Row spacing matches the day editor's set table.
        return VStack(alignment: .leading, spacing: 8) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 6) {
                    Text("Set").frame(width: 44)
                    Text("Previous").frame(width: 64)
                    if columns.weight { Text(item.mode == .bodyweight ? "+\(unit)" : unit).frame(maxWidth: .infinity) }
                    if columns.reps { Text("Reps").frame(maxWidth: .infinity) }
                    if columns.time { Text("Time").frame(maxWidth: .infinity) }
                    if columns.distance { Text("Meters").frame(maxWidth: .infinity) }
                    Text("RPE").frame(maxWidth: columns.hasMeasurements ? 44 : .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 2)
            }
            if !warmups.isEmpty {
                SetGroupLabel(title: "Warm-up", color: palette.warmup)
                ForEach(warmups, id: \.element.id) { index, set in row(set, index: index) }
            }
            if !work.isEmpty {
                if !warmups.isEmpty { SetGroupLabel(title: item.mode == .cardio ? "Intervals" : "Working sets", color: .secondary).padding(.top, 6) }
                ForEach(work, id: \.element.id) { index, set in row(set, index: index) }
            }
        }
    }
    private func row(_ set: LoggedSet, index: Int) -> some View {
        LiveSetRow(exerciseID: exerciseID, setID: set.id, index: index) { sheet = $0 }
    }
    private func addWarmup() {
        store.perform { data in
            try data.addSessionSet(to: exerciseID, warmup: true)
            data.setExerciseExpanded(exerciseID, expanded: true, focus: true)
        }
    }
    var completed: Bool { guard let item else { return false }; return !item.sets.isEmpty && item.sets.allSatisfy { $0.completedAt != nil } }
    var autoCollapseReady: Bool {
        completed && item?.collapsed != true && item?.keepExpanded != true && sheet == nil && !removing && !noteFocused && store.data.settings.collapsesCompletedExercises
    }
    /// Collapsed summary in the standard prescription form, for example "3 × 8–10 · 65 lb".
    func compactSummary(_ item: SessionExercise) -> String {
        let main = Set(prescribedWork(item.sets.map(\.plan)).map(\.id))
        let work = item.sets.filter { main.contains($0.plan.id) }
        guard let first = work.first else { return counted(item.sets.count, "warm-up") }
        var parts: [String] = []
        if let target = first.plan.repTarget { parts.append("\(work.count) × \(displayTarget(target))") }
        else if let seconds = first.plan.seconds { parts.append(work.count > 1 ? "\(work.count) × \(clockText(seconds))" : clockText(seconds)) }
        else { parts.append(counted(work.count, "set")) }
        if let load = loadSummary([first.weight], mode: item.mode, unit: store.data.settings.unit) { parts.append(load) }
        return parts.joined(separator: " · ")
    }
}

struct CardioTimer: View {
    @EnvironmentObject var store: AppStore
    let exerciseID: UUID
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        if let item {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in Text(clockText(item.timerElapsed + (item.timerStartedAt.map { context.date.timeIntervalSince($0) } ?? 0))).font(.title3.weight(.semibold)).monospacedDigit() }
                Spacer()
                Button(item.timerStartedAt == nil ? "Start timer" : "Pause") {
                    if item.timerStartedAt == nil, store.data.activeSession?.pausedAt != nil { store.pauseWorkout(false) }
                    store.editExercise(exerciseID) { e in if let start = e.timerStartedAt { e.timerElapsed += Date().timeIntervalSince(start); e.timerStartedAt = nil } else { e.timerStartedAt = Date() } }
                }.buttonStyle(.bordered).accessibilityIdentifier("workout.\(exerciseID).timerStart")
                if item.timerStartedAt != nil || item.timerElapsed > 0 {
                    Button("Log time") {
                        guard let set = item.sets.first(where: { $0.completedAt == nil }) else { return }
                        let elapsed = item.timerElapsed + (item.timerStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
                        store.editSet(exerciseID, set.id) { $0.seconds = elapsed }
                        store.toggle(exerciseID, set.id)
                        store.editExercise(exerciseID) { $0.timerStartedAt = nil; $0.timerElapsed = 0 }
                    }.buttonStyle(AccentButtonStyle()).accessibilityIdentifier("workout.\(exerciseID).timerLog")
                }
            }
        }
    }
}
