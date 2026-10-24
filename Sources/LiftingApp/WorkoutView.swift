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
    @State private var draggingExercise: UUID?
    @State private var adding = false
    @State private var finishing = false
    @State private var discard = false
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
                        ForEach(session.exercises) { exercise in WorkoutExerciseCard(exerciseID: exercise.id, dragging: $draggingExercise).id(exercise.id) }
                        Button { adding = true } label: { Label("Add Exercise", systemImage: "plus") }.buttonStyle(FieldButtonStyle()).padding(.top, 4)
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                }
            }.background(palette.background)
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
            .sheet(isPresented: $sessionNotes) {
                NavigationStack {
                    ThemedForm {
                        Section("Name") { SavedNameField(name: store.data.activeSession?.name ?? "") { value in store.editActive { $0.name = value } } }
                        Section("Note") { TextField("Workout note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(5...12) }
                    }.formStyle(.grouped).navigationTitle("Workout").inlineTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { sessionNotes = false } } }
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
                            MetricTile(value: "\(number(store.data.settings.unit.display(session.volume), decimals: 0)) \(store.data.settings.unit.rawValue)", label: "Volume")
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
                stat("Volume", "\(number(store.data.settings.unit.display(session.volume), decimals: 0)) \(store.data.settings.unit.rawValue)")
                stat("Sets", "\(session.completedSets) of \(session.totalSets)")
            }
            CapsuleProgress(value: session.totalSets == 0 ? 0 : Double(session.completedSets) / Double(session.totalSets))
        }.padding(.horizontal, 4).padding(.bottom, 4)
    }
    func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.figure(17)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).accessibilityElement(children: .combine)
    }
}

/// Icon and title with tighter spacing than the default label style.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 5) { configuration.icon.imageScale(.small); configuration.title } }
}

struct RestBar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.palette) var palette
    var body: some View {
        if let deadline = store.data.restDeadline {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = deadline.timeIntervalSince(context.date)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(palette.rest.opacity(0.25), lineWidth: 4)
                        Circle().trim(from: 0, to: total > 0 ? max(0, remaining) / total : 0).stroke(palette.rest, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    }.frame(width: 30, height: 30).accessibilityHidden(true)
                    Text(remaining > 0 ? clockText(remaining) : "Rest done").font(.figure(22, weight: .bold)).foregroundStyle(remaining > 0 ? Color.primary : palette.rest)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(remaining > 0 ? "Rest, \(clockText(remaining)) left" : "Rest complete")
                    Group {
                        Button("−15") { store.adjustRest(-15) }.accessibilityLabel("Subtract 15 seconds")
                        Button("+15") { store.adjustRest(15) }.accessibilityLabel("Add 15 seconds")
                    }.font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(palette.rest)
                    .frame(width: 48, height: 36).background(palette.rest.opacity(palette.dark ? 0.2 : 0.12), in: Capsule()).buttonStyle(.plain)
                    Button("Skip", action: store.skipRest).font(.subheadline.weight(.semibold)).foregroundStyle(palette.on(.rest))
                        .frame(width: 56, height: 36).background(palette.rest, in: Capsule()).buttonStyle(.plain).accessibilityIdentifier("rest.skip")
                }
                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
                .background(palette.card, in: Capsule())
                .shadow(color: .black.opacity(palette.dark ? 0.5 : 0.12), radius: 16, y: 4)
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            .task(id: deadline) { total = max(1, deadline.timeIntervalSince(store.restStartedAt ?? Date())) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    @State private var total: Double = 1
}

struct WorkoutExerciseCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    @Binding var dragging: UUID?
    @State private var substituting = false
    @State private var technique: TechniqueKind?
    @State private var editVariant: Variant?
    @State private var plates = false
    @State private var removing = false
    @FocusState private var noteFocused: Bool
    @State private var restEdit: NumericEdit?
    @State private var linking = false
    @State private var warmups = false
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.snappy) { _ = store.perform { $0.setExerciseExpanded(exerciseID, expanded: item.collapsed == true, focus: item.collapsed == true) } }
                    } label: { header(item) }
                    .modifier(ExerciseDragHandle(id: exerciseID, enabled: true, dragging: $dragging))
                    .buttonStyle(.plain).accessibilityLabel("\(item.collapsed == true ? "Expand" : "Collapse") \(item.name)").accessibilityIdentifier("workout.\(exerciseID).collapse").accessibilityValue("\(item.collapsed == true ? "Collapsed" : "Expanded"), \(item.sets.filter { $0.completedAt != nil }.count) of \(item.sets.count) sets")
                    .modifier(ReorderActions(canMoveUp: store.data.activeSession?.exercises.first?.id != exerciseID, canMoveDown: store.data.activeSession?.exercises.last?.id != exerciseID) { offset in
                        store.perform { $0.moveSessionExercise(exerciseID, offset: offset) }
                    })
                    Menu {
                        Button("Swap Exercise", systemImage: "arrow.triangle.2.circlepath") { substituting = true }.accessibilityIdentifier("workout.\(item.id).substitute")
                        Button("Superset / Circuit", systemImage: "link") { linking = true }
                        Divider()
                        Button("Add Warm-up Set", systemImage: "plus") { appendSet(item, warmup: true); store.perform { $0.setExerciseExpanded(exerciseID, expanded: true, focus: true) } }.disabled(item.mode == .cardio)
                        Button("Apply Warm-up Preset", systemImage: "flame") { warmups = true }.disabled(item.mode == .cardio)
                        Button("Edit Saved Prescription", systemImage: "slider.horizontal.3") { editVariant = store.data.variant(item.variantID) }
                        Button("Save Weights to This Day", systemImage: "square.and.arrow.down") { store.perform { try $0.saveSessionWeights(exerciseID) } }
                        Button("Plate Calculator", systemImage: "circle.grid.2x1") { plates = true }.disabled(item.mode == .cardio)
                        Divider()
                        Button("Remove from Workout", systemImage: "trash", role: .destructive) { removing = true }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).frame(width: 32, height: 44) }.compactMenu().foregroundStyle(.secondary).accessibilityLabel("Options for \(item.name)").accessibilityIdentifier("workout.\(exerciseID).options")
                }
                if item.collapsed != true {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        if item.mode == .strength {
                            Text(weightSummary(item.sets.filter { $0.plan.kind != .warmup }.compactMap(\.weight), unit: store.data.settings.unit))
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                .accessibilityLabel("Working sets, " + weightSummary(item.sets.filter { $0.plan.kind != .warmup }.compactMap(\.weight), unit: store.data.settings.unit))
                        }
                        Button { restEdit = NumericEdit(title: "Rest (seconds)", context: item.name, value: Double(item.restSeconds), step: 15, maximum: 86400, integer: true) { value in store.editExercise(exerciseID) { $0.restSeconds = Int(value ?? 0) } } } label: { token("Rest", clockText(Double(item.restSeconds)), palette.rest) }
                            .accessibilityLabel("Rest between sets for \(item.name)")
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    }.buttonStyle(.plain)
                    TextField("Add a note", text: Binding(get: { self.item?.notes ?? "" }, set: { value in store.editExercise(exerciseID) { $0.notes = value } }), axis: .vertical)
                        .font(.subheadline).lineLimit(1...5).foregroundStyle(.primary).focused($noteFocused).padding(.bottom, 4).accessibilityIdentifier("workout.\(exerciseID).noteField")
                    if let from = item.substitutedFrom { Label("Instead of \(from)", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary) }
                    if !item.recurringNotes.isEmpty { Label(item.recurringNotes, systemImage: "pin.fill").font(.footnote).foregroundStyle(.secondary) }
                    if item.mode == .cardio || item.sets.contains(where: { $0.seconds != nil }) { CardioTimer(exerciseID: exerciseID) }
                    if !item.sets.isEmpty { setTable(item) }
                    let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    actions {
                        Button { appendSet(item) } label: { Label(item.mode == .cardio ? "Add Interval" : item.sets.last?.plan.kind == .myoMini ? "Add Mini-set" : "Add Set", systemImage: "plus") }.buttonStyle(FieldButtonStyle())
                        if item.mode != .cardio {
                            ForEach(0..<2, id: \.self) { index in quickButton(index: index, item: item) }
                        }
                    }.padding(.top, 2)
                }
            }.card(padding: 16)
            .modifier(ExerciseDropTarget(id: exerciseID, dragging: $dragging) { source, target, after in
                store.perform { $0.moveSessionExercise(source, relativeTo: target, after: after) }
            })
            .task(id: autoCollapseReady) {
                guard autoCollapseReady else { return }
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                store.collapseCompleted(exerciseID)
            }
            .sheet(isPresented: $substituting) {
                ExercisePicker(title: "Substitute", similarMuscle: store.data.exercise(item.exerciseID)?.muscle, substitution: true, onSubstitute: { exercise, future in store.perform { try $0.substitute(sessionExerciseID: exerciseID, with: exercise.id, future: future) } }).environmentObject(store).sheetSize()
            }
            .sheet(item: $technique) { kind in
                let variant = store.data.variant(item.variantID)!
                TechniqueEditor(kind: kind, workingWeight: item.workingLoad(fallback: variant.workingWeight), rounding: item.roundingIncrement ?? variant.rounding, live: true) { plans, replace, future in
                    applyTechnique(plans, kind: kind, replace: replace, future: future)
                }.environmentObject(store).sheetSize()
            }
            .sheet(item: $editVariant) { VariantEditor(variant: $0).environmentObject(store).sheetSize() }
            .sheet(isPresented: $plates) { PlateView(initialWeight: store.data.settings.unit.display(item.sets.last?.weight ?? 0)).environmentObject(store).sheetSize() }
            .sheet(item: $restEdit) { NumberEditor(edit: $0) }
            .sheet(isPresented: $linking) { LinkedExerciseEditor(exerciseID: exerciseID).environmentObject(store).sheetSize() }
            .sheet(isPresented: $warmups) { ApplyWarmupPreset(exerciseID: exerciseID).environmentObject(store).sheetSize() }
            .confirmationDialog("Remove \(item.name)?", isPresented: $removing) { Button("Remove from workout", role: .destructive) { store.editActive { $0.exercises.removeAll { $0.id == exerciseID } } } } message: { Text("This removes its sets from the current workout.") }
        }
    }
    @ViewBuilder func header(_ item: SessionExercise) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                if let session = store.data.activeSession, let title = session.linkTitle(for: exerciseID) {
                    let partners = session.linkedExercises(for: exerciseID).filter { $0.id != exerciseID }.map(\.name).formatted(.list(type: .and))
                    Label("\(title) with \(partners)", systemImage: "link").font(.footnote.weight(.medium)).foregroundStyle(palette.technique).lineLimit(2)
                }
                if item.collapsed == true { Text(compactSummary(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            if completed { Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.completed) }
            else { Text("\(item.sets.filter { $0.completedAt != nil }.count) of \(item.sets.count)").font(.figure(13, weight: .medium)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
    /// One column header for the exercise, then warm-ups and working sets under small group labels.
    func setTable(_ item: SessionExercise) -> some View {
        let columns = SetTableColumns(item: item)
        let warmups = Array(item.sets.enumerated()).filter { $0.element.plan.kind == .warmup }
        let work = Array(item.sets.enumerated()).filter { $0.element.plan.kind != .warmup }
        return VStack(alignment: .leading, spacing: 2) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 6) {
                    Text("Set").frame(width: 44)
                    Text("Previous").frame(width: 64)
                    if columns.weight { Text(store.data.settings.unit.rawValue).frame(maxWidth: .infinity) }
                    if columns.reps { Text("Reps").frame(maxWidth: .infinity) }
                    if columns.time { Text("Time").frame(maxWidth: .infinity) }
                    if columns.distance { Text("Meters").frame(maxWidth: .infinity) }
                    Text("RPE").frame(maxWidth: columns.hasMeasurements ? 44 : .infinity)
                    Color.clear.frame(width: 40, height: 1)
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 2).padding(.bottom, 2)
            }
            if !warmups.isEmpty {
                groupLabel("Warm-up", color: palette.warmup)
                ForEach(warmups, id: \.element.id) { index, set in LiveSetRow(exerciseID: exerciseID, setID: set.id, index: index) }
            }
            if !work.isEmpty {
                if !warmups.isEmpty { groupLabel(item.mode == .cardio ? "Intervals" : "Working sets", color: .secondary).padding(.top, 6) }
                ForEach(work, id: \.element.id) { index, set in LiveSetRow(exerciseID: exerciseID, setID: set.id, index: index) }
            }
        }
    }
    private func quickButton(index: Int, item: SessionExercise) -> some View {
        QuickAddButton(index: index) { runQuickAdd($0, item: item) }
            .frame(width: typeSize.isAccessibilitySize ? nil : 96)
            .accessibilityIdentifier(index == 0 ? "workout.\(exerciseID).addDrop" : "workout.\(exerciseID).addMyo")
    }
    private func runQuickAdd(_ slot: QuickAdd, item: SessionExercise) {
        switch slot {
        case .drop: technique = .drop
        case .myo: technique = .myo
        case .warmup: appendSet(item, warmup: true); store.perform { $0.setExerciseExpanded(exerciseID, expanded: true, focus: true) }
        case .working: appendSet(item)
        case .myoActivation: store.perform { try $0.addTypedSet(to: exerciseID, kind: .myoActivation) }
        case .myoMini: store.perform { try $0.addTypedSet(to: exerciseID, kind: .myoMini) }
        case .failure: store.perform { try $0.addTypedSet(to: exerciseID, kind: .failure) }
        case .custom(let id): store.perform { try $0.addTypedSet(to: exerciseID, kind: $0.setType(id)?.countsAs ?? .working, customTypeID: id) }
        }
    }
    private func groupLabel(_ title: String, color: Color) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(color).padding(.leading, 2).padding(.vertical, 2)
    }
    private func token(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Text(title).foregroundStyle(.secondary); Text(value).foregroundStyle(color).fontWeight(.semibold).monospacedDigit() }.font(.subheadline).frame(minHeight: 30).contentShape(Rectangle())
    }
    var completed: Bool { guard let item else { return false }; return !item.sets.isEmpty && item.sets.allSatisfy { $0.completedAt != nil } }
    var autoCollapseReady: Bool { completed && item?.collapsed != true && item?.keepExpanded != true && technique == nil && editVariant == nil && !substituting && !noteFocused && restEdit == nil && store.data.settings.collapsesCompletedExercises }
    /// Collapsed summary in the standard prescription form, for example "3 × 8–10 · 65 lb".
    func compactSummary(_ item: SessionExercise) -> String {
        let main = Set(prescribedWork(item.sets.map(\.plan)).map(\.id))
        let work = item.sets.filter { main.contains($0.plan.id) }
        guard let first = work.first else { return counted(item.sets.count, "warm-up") }
        var parts: [String] = []
        if let target = first.plan.repTarget { parts.append("\(work.count) × \(target.replacingOccurrences(of: "-", with: "–"))") }
        else if let seconds = first.plan.seconds { parts.append(work.count > 1 ? "\(work.count) × \(clockText(seconds))" : clockText(seconds)) }
        else { parts.append(counted(work.count, "set")) }
        if let weight = first.weight { parts.append("\(number(store.data.settings.unit.display(weight))) \(store.data.settings.unit.rawValue)") }
        return parts.joined(separator: " · ")
    }
    func appendSet(_ item: SessionExercise, warmup: Bool = false) {
        store.perform { try $0.addSessionSet(to: exerciseID, warmup: warmup) }
    }
    func applyTechnique(_ plans: [SetPlan], kind: TechniqueKind, replace: Bool, future: Bool) {
        store.perform { try $0.applyTechnique(to: exerciseID, plans: plans, isDrop: kind == .drop, replaceRemaining: replace, saveFuture: future) }
        if kind == .drop { store.cancelRestAlert() }
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
