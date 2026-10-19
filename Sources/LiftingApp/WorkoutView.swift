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
    @State private var adding = false
    @State private var finishing = false
    @State private var discard = false
    @State private var sessionNotes = false
    @State private var linking = false
    @State private var warmups = false
    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                if let session = store.data.activeSession {
                    LazyVStack(spacing: 12) {
                        WorkoutSummaryHeader(session: session)
                        ForEach(session.exercises) { exercise in WorkoutExerciseCard(exerciseID: exercise.id).id(exercise.id) }
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
                ToolbarItem(placement: .cancellationAction) { Button { store.workoutPresented = false } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Minimize workout") }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Name and Note", systemImage: "note.text") { sessionNotes = true }.accessibilityIdentifier("workout.note")
                        Button("Superset / Circuit", systemImage: "link") { linking = true }.disabled((store.data.activeSession?.exercises.count ?? 0) < 2).accessibilityIdentifier("workout.link")
                        Button("Apply Warm-up Preset", systemImage: "flame") { warmups = true }
                        Divider()
                        Button("Collapse All", systemImage: "chevron.up") { store.perform { $0.setAllExercisesExpanded(false) } }.accessibilityIdentifier("workout.collapseAll")
                        Button("Expand All", systemImage: "chevron.down") { store.perform { $0.setAllExercisesExpanded(true) } }.accessibilityIdentifier("workout.expandAll")
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Workout options").accessibilityIdentifier("workout.options")
                }
                if #available(iOS 26.0, macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
                ToolbarItem(placement: .primaryAction) {
                    Button("Finish") { finishing = true }.fontWeight(.semibold).primaryButtonStyle().accessibilityIdentifier("workout.finish")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { RestBar().animation(.snappy, value: store.data.restDeadline) }
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.fontWeight(.semibold)
                }
            }
            #endif
            .sheet(isPresented: $adding) { ExercisePicker(title: "Add exercise", onSelect: store.addToWorkout).environmentObject(store).sheetSize() }
            .sheet(isPresented: $linking) { LinkedExerciseEditor().environmentObject(store).sheetSize() }
            .sheet(isPresented: $warmups) { ApplyWarmupPreset().environmentObject(store).sheetSize() }
            .sheet(isPresented: $finishing) { finishSheet }
            .sheet(isPresented: $sessionNotes) {
                NavigationStack {
                    ThemedForm {
                        Section("Name") { SavedNameField(name: store.data.activeSession?.name ?? "") { value in store.editActive { $0.name = value } } }
                        Section("Note") { TextField("Workout note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(5...12) }
                    }.formStyle(.grouped).navigationTitle("Workout").inlineTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sessionNotes = false } } }
                }.sheetSize()
            }
        }.tint(palette.action)
        .alert("Could not complete action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onAppear {
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
    var finishSheet: some View {
        NavigationStack {
            ThemedForm {
                if let session = store.data.activeSession {
                    Section {
                        HStack {
                            MetricTile(value: "\(session.completedSets)", label: "Sets")
                            MetricTile(value: clockText(Date().timeIntervalSince(session.startedAt)), label: "Duration")
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
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in stat("Duration", clockText(context.date.timeIntervalSince(session.startedAt))) }
                stat("Volume", "\(number(store.data.settings.unit.display(session.volume), decimals: 0)) \(store.data.settings.unit.rawValue)")
                stat("Sets", "\(session.completedSets) of \(session.totalSets)")
            }
            CapsuleProgress(value: session.totalSets == 0 ? 0 : Double(session.completedSets) / Double(session.totalSets))
        }.padding(.horizontal, 4).padding(.bottom, 4)
    }
    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.figure(17)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
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
    @State private var substituting = false
    @State private var technique: TechniqueKind?
    @State private var editVariant: Variant?
    @State private var plates = false
    @State private var removing = false
    @FocusState private var noteFocused: Bool
    @State private var workingWeight = false
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
                    .buttonStyle(.plain).accessibilityLabel("\(item.collapsed == true ? "Expand" : "Collapse") \(item.name)").accessibilityIdentifier("workout.\(exerciseID).collapse").accessibilityValue("\(item.collapsed == true ? "Collapsed" : "Expanded"), \(item.sets.filter { $0.completedAt != nil }.count) of \(item.sets.count) sets")
                    Menu {
                        Button("Swap Exercise", systemImage: "arrow.triangle.2.circlepath") { substituting = true }.accessibilityIdentifier("workout.\(item.id).substitute")
                        Button("Superset / Circuit", systemImage: "link") { linking = true }
                        Divider()
                        Button("Add Warm-up Set", systemImage: "plus") { appendSet(item, warmup: true); store.perform { $0.setExerciseExpanded(exerciseID, expanded: true, focus: true) } }.disabled(item.mode == .cardio)
                        Button("Apply Warm-up Preset", systemImage: "flame") { warmups = true }.disabled(item.mode == .cardio)
                        Button("Edit Prescription", systemImage: "slider.horizontal.3") { editVariant = store.data.variant(item.variantID) }
                        Button("Plate Calculator", systemImage: "circle.grid.2x1") { plates = true }.disabled(item.mode == .cardio)
                        Divider()
                        Button("Move Up", systemImage: "arrow.up") { store.perform { $0.moveSessionExercise(exerciseID, offset: -1) } }.disabled(store.data.activeSession?.exercises.first?.id == exerciseID)
                        Button("Move Down", systemImage: "arrow.down") { store.perform { $0.moveSessionExercise(exerciseID, offset: 1) } }.disabled(store.data.activeSession?.exercises.last?.id == exerciseID)
                        Button("Remove from Workout", systemImage: "trash", role: .destructive) { removing = true }
                    } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 32, height: 44) }.compactMenu().foregroundStyle(.secondary).accessibilityLabel("Options for \(item.name)").accessibilityIdentifier("workout.\(exerciseID).options")
                }
                if item.collapsed != true {
                    HStack(spacing: 16) {
                        if item.mode == .strength {
                            Button { workingWeight = true } label: { token("Working", "\(number(store.data.settings.unit.display(item.workingLoad(fallback: store.data.variant(item.variantID)?.workingWeight ?? 0)))) \(store.data.settings.unit.rawValue)", palette.action) }
                                .accessibilityLabel("Working weight for \(item.name)").accessibilityIdentifier("workout.\(exerciseID).workingWeight")
                        }
                        Button { restEdit = NumericEdit(title: "Rest (seconds)", context: item.name, value: Double(item.restSeconds), step: 15, maximum: 86400, integer: true) { value in store.editExercise(exerciseID) { $0.restSeconds = Int(value ?? 0) } } } label: { token("Rest", clockText(Double(item.restSeconds)), palette.rest) }
                            .accessibilityLabel("Rest between sets for \(item.name)")
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain)
                    TextField("Add a note", text: Binding(get: { self.item?.notes ?? "" }, set: { value in store.editExercise(exerciseID) { $0.notes = value } }), axis: .vertical)
                        .font(.subheadline).lineLimit(1...5).foregroundStyle(.primary).focused($noteFocused).padding(.bottom, 4).accessibilityIdentifier("workout.\(exerciseID).noteField")
                    if let from = item.substitutedFrom { Label("Instead of \(from)", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary) }
                    if !item.recurringNotes.isEmpty { Label(item.recurringNotes, systemImage: "pin.fill").font(.footnote).foregroundStyle(.secondary) }
                    if item.mode == .cardio || item.sets.contains(where: { $0.seconds != nil }) { CardioTimer(exerciseID: exerciseID) }
                    if !item.sets.isEmpty { setTable(item) }
                    HStack(spacing: 8) {
                        Button { appendSet(item) } label: { Label(item.mode == .cardio ? "Add Interval" : item.sets.last?.plan.kind == .myoMini ? "Add Mini-set" : "Add Set", systemImage: "plus") }.buttonStyle(FieldButtonStyle())
                        if item.mode != .cardio {
                            ForEach(Array(QuickAdd.slots(store.data).enumerated()), id: \.offset) { index, slot in quickButton(slot, index: index, item: item) }
                        }
                    }.padding(.top, 2)
                }
            }.card(padding: 16)
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
            .sheet(isPresented: $workingWeight) { WorkingWeightEditor(exerciseID: exerciseID).environmentObject(store).sheetSize() }
            .sheet(item: $restEdit) { NumericPad(edit: $0) }
            .sheet(isPresented: $linking) { LinkedExerciseEditor(exerciseID: exerciseID).environmentObject(store).sheetSize() }
            .sheet(isPresented: $warmups) { ApplyWarmupPreset(exerciseID: exerciseID).environmentObject(store).sheetSize() }
            .confirmationDialog("Remove \(item.name)?", isPresented: $removing) { Button("Remove from workout", role: .destructive) { store.editActive { $0.exercises.removeAll { $0.id == exerciseID } } } } message: { Text("This removes its sets from the current workout.") }
        }
    }
    @ViewBuilder func header(_ item: SessionExercise) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                if let session = store.data.activeSession, let title = session.linkTitle(for: exerciseID) {
                    let partners = session.linkedExercises(for: exerciseID).filter { $0.id != exerciseID }.map(\.name).formatted(.list(type: .and))
                    Label("\(title) with \(partners)", systemImage: "link").font(.footnote.weight(.medium)).foregroundStyle(palette.technique).lineLimit(2)
                }
                if item.collapsed == true { Text(compactSummary(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if completed { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(palette.completed) }
            else { Text("\(item.sets.filter { $0.completedAt != nil }.count) of \(item.sets.count)").font(.figure(13, weight: .medium)).foregroundStyle(.secondary) }
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
    /// One column header for the exercise, then warm-ups and working sets under small group labels.
    func setTable(_ item: SessionExercise) -> some View {
        let columns = SetTableColumns(item: item)
        let warmups = Array(item.sets.enumerated()).filter { $0.element.plan.kind == .warmup }
        let work = Array(item.sets.enumerated()).filter { $0.element.plan.kind != .warmup }
        return VStack(alignment: .leading, spacing: 2) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 6) {
                    Text("Set").frame(width: 32)
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
    /// A quick-add slot. Long-press to swap it for another set type; the choice applies to every exercise.
    private func quickButton(_ slot: QuickAdd, index: Int, item: SessionExercise) -> some View {
        Button { runQuickAdd(slot, item: item) } label: { Text(slot.title(store.data)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(slot.color(palette)) }
            .buttonStyle(FieldButtonStyle(role: .technique)).frame(width: 80)
            .contextMenu {
                Section("Swap this button for") {
                    ForEach(QuickAdd.options(store.data), id: \.self) { option in
                        Button { store.perform { d in var slots = QuickAdd.slots(d).map(\.raw); slots[index] = option.raw; d.settings.quickAdd = slots } } label: {
                            if option == slot { Label(option.title(store.data), systemImage: "checkmark") } else { Text(option.title(store.data)) }
                        }
                    }
                }
                NavigationLink { SetTypesView() } label: { Label("Manage Set Types", systemImage: "square.stack.3d.up") }
            }
            .accessibilityHint("Long-press to swap for another set type")
            .accessibilityIdentifier(index == 0 ? "workout.\(exerciseID).addDrop" : "workout.\(exerciseID).addMyo")
    }
    private func runQuickAdd(_ slot: QuickAdd, item: SessionExercise) {
        switch slot {
        case .drop: technique = .drop
        case .myo: technique = .myo
        case .warmup: appendSet(item, warmup: true); store.perform { $0.setExerciseExpanded(exerciseID, expanded: true, focus: true) }
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
    var autoCollapseReady: Bool { completed && item?.collapsed != true && item?.keepExpanded != true && technique == nil && editVariant == nil && !substituting && !workingWeight && !noteFocused && restEdit == nil && store.data.settings.autoCollapseCompleted == true }
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

struct WorkingWeightEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let exerciseID: UUID
    @State private var weight = 0.0
    @State private var future = false
    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    HStack { Text("Weight (\(store.data.settings.unit.rawValue))"); Spacer(); TextField("0", value: $weight, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 110) }
                } footer: { Text("Updates remaining working sets and percentage-based sets in this workout.") }
                Section { Toggle("Save to this day", isOn: $future) }
            }.formStyle(.grouped).navigationTitle("Working Weight").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { if store.perform({ try $0.setWorkingWeight($0.settings.unit.kilograms(weight), for: exerciseID, saveFuture: future) }) { dismiss() } }.disabled(!weight.isFinite || weight < 0) }
            }
        }.onAppear { if let item = store.data.activeSession?.exercises.first(where: { $0.id == exerciseID }) { weight = store.data.settings.unit.display(item.workingLoad(fallback: store.data.variant(item.variantID)?.workingWeight ?? 0)) } }
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
