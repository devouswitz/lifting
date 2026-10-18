import SwiftUI
import LiftingCore
#if os(iOS)
import UIKit
#endif

struct WorkoutView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var adding = false
    @State private var finishing = false
    @State private var discard = false
    @State private var sessionNotes = false
    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
            ScrollView {
                if let session = store.data.activeSession {
                    LazyVStack(spacing: 12) {
                        HStack {
                            TimelineView(.periodic(from: .now, by: 1)) { context in Text(clockText(context.date.timeIntervalSince(session.startedAt))).monospacedDigit() }
                            Spacer(); Text("\(session.completedSets) / \(session.totalSets) sets")
                        }.font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                        ForEach(session.exercises) { exercise in WorkoutExerciseCard(exerciseID: exercise.id).id(exercise.id) }
                        Button { adding = true } label: { Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity).padding(10) }.buttonStyle(.bordered)
                    }.padding(16)
                }
            }.background(Palette.background(scheme))
            .onChange(of: store.autoFocusRevision) { _, _ in
                guard let id = store.autoFocusedExerciseID else { return }
                if reduceMotion { reader.scrollTo(id, anchor: .top) }
                else { withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(id, anchor: .top) } }
            }
            }
            .navigationTitle(store.data.activeSession?.name ?? "Workout").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { store.workoutPresented = false } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Minimize workout") }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                    Menu {
                        Button("Workout Note", systemImage: "note.text") { sessionNotes = true }.accessibilityIdentifier("workout.note")
                        Button("Collapse All", systemImage: "chevron.up") { store.perform { $0.setAllExercisesExpanded(false) } }.accessibilityIdentifier("workout.collapseAll")
                        Button("Expand All", systemImage: "chevron.down") { store.perform { $0.setAllExercisesExpanded(true) } }.accessibilityIdentifier("workout.expandAll")
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Workout options").accessibilityIdentifier("workout.options")
                    Button("Finish") { finishing = true }.fontWeight(.semibold).accessibilityIdentifier("workout.finish")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { RestBar() }
            .sheet(isPresented: $adding) { ExercisePicker(title: "Add exercise", onSelect: store.addToWorkout).environmentObject(store).sheetSize() }
            .sheet(isPresented: $finishing) { finishSheet }
            .sheet(isPresented: $sessionNotes) {
                NavigationStack {
                    Form { TextField("Workout name", text: Binding(get: { store.data.activeSession?.name ?? "" }, set: { value in if !value.isEmpty { store.editActive { $0.name = value } } })); TextField("Workout note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(5...12) }.formStyle(.grouped).navigationTitle("Workout note").toolbar { Button("Done") { sessionNotes = false } }
                }.sheetSize()
            }
            .confirmationDialog("Discard this workout?", isPresented: $discard) { Button("Discard workout", role: .destructive, action: store.discard) }
        }.tint(Palette.tint(scheme))
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
            Form {
                if let session = store.data.activeSession {
                    Section {
                        HStack { MetricTile(value: "\(session.completedSets)", label: "Sets"); MetricTile(value: "\(number(store.data.settings.unit.display(session.volume), decimals: 0))", label: "Volume (\(store.data.settings.unit.rawValue))") }
                        Text("Duration: \(clockText(Date().timeIntervalSince(session.startedAt)))").foregroundStyle(.secondary)
                        if session.completedSets < session.totalSets { Text("\(session.totalSets - session.completedSets) sets will be saved as skipped.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Section("Workout note") { TextField("Note", text: Binding(get: { store.data.activeSession?.notes ?? "" }, set: { value in store.editActive { $0.notes = value } }), axis: .vertical).lineLimit(3...6) }
                    Button("Save workout") { store.finish(); finishing = false }.disabled(session.completedSets == 0).accessibilityIdentifier("workout.save")
                    Button("Discard workout", role: .destructive) { finishing = false; discard = true }
                }
            }.formStyle(.grouped).navigationTitle("Finish workout").inlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { finishing = false } } }
        }.sheetSize()
    }
}

struct RestBar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    var body: some View {
        if let deadline = store.data.restDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                    Text(deadline > context.date ? clockText(deadline.timeIntervalSince(context.date)) : "Rest complete").font(.headline).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                    Button("−15") { store.adjustRest(-15) }.buttonStyle(.bordered)
                    Button("+15") { store.adjustRest(15) }.buttonStyle(.bordered)
                    Button("Skip", action: store.skipRest).accessibilityIdentifier("rest.skip")
                }.padding(12).background(Palette.surface(scheme)).overlay(alignment: .top) { Divider() }
            }
        }
    }
}

struct WorkoutExerciseCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    @State private var substituting = false
    @State private var technique: TechniqueKind?
    @State private var editVariant: Variant?
    @State private var note = false
    @State private var plates = false
    @State private var removing = false
    @State private var workingWeight = false
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 4) {
                    Button {
                        store.perform { $0.setExerciseExpanded(exerciseID, expanded: item.collapsed == true) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.collapsed == true ? "chevron.right" : "chevron.down").font(.subheadline.weight(.semibold)).frame(width: 18, height: 26)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    if completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                    Text(item.name).font(.title3.weight(.semibold))
                                    if !item.notes.isEmpty { Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary) }
                                }
                                if item.collapsed == true {
                                    Text(compactSummary(item)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                } else { Chip(title: item.label) }
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 44, alignment: .top).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(item.collapsed == true ? "Expand" : "Collapse") \(item.name)").accessibilityIdentifier("workout.\(exerciseID).collapse").accessibilityValue("\(item.collapsed == true ? "Collapsed" : "Expanded"), \(item.sets.filter { $0.completedAt != nil }.count) of \(item.sets.count) sets")
                    Menu {
                        Button("Focus This Exercise") { store.perform { $0.setExerciseExpanded(exerciseID, expanded: true, focus: true) } }
                        Button("Move up") { store.perform { $0.moveSessionExercise(exerciseID, offset: -1) } }
                        Button("Move down") { store.perform { $0.moveSessionExercise(exerciseID, offset: 1) } }
                        Divider()
                        Button("Edit Saved Prescription") { editVariant = store.data.variant(item.variantID) }
                        Button("Add warm-up") { appendSet(item, warmup: true); store.perform { $0.setExerciseExpanded(exerciseID, expanded: true) } }
                        Button("Plate calculator") { plates = true }.disabled(item.mode == .cardio)
                        Button("Remove from workout", role: .destructive) { removing = true }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(item.name)").accessibilityIdentifier("workout.\(exerciseID).options")
                }
                if item.collapsed != true {
                HStack {
                    Button { substituting = true } label: { Label("Substitute", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.bordered).accessibilityIdentifier("workout.\(item.id).substitute")
                    Spacer()
                    if item.mode == .strength { Button { workingWeight = true } label: { Label("\(number(store.data.settings.unit.display(item.workingLoad(fallback: store.data.variant(item.variantID)?.workingWeight ?? 0)))) \(store.data.settings.unit.rawValue)", systemImage: "scalemass") }.buttonStyle(.bordered).accessibilityLabel("Set working weight for \(item.name)").accessibilityIdentifier("workout.\(exerciseID).workingWeight") }
                }
                Text("Rest \(clockText(Double(item.restSeconds)))").font(.caption).foregroundStyle(.secondary)
                if let from = item.substitutedFrom { Label("Instead of \(from)", systemImage: "arrow.left.arrow.right").font(.caption).foregroundStyle(.secondary) }
                if !item.recurringNotes.isEmpty { Label(item.recurringNotes, systemImage: "pin.fill").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if item.mode == .cardio || item.sets.contains(where: { $0.seconds != nil }) { CardioTimer(exerciseID: exerciseID) }
                VStack(spacing: 4) {
                    ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                        LiveSetRow(exerciseID: exerciseID, setID: set.id, index: index)
                    }
                }
                if item.mode != .cardio {
                    HStack(spacing: 8) {
                        Button { appendSet(item) } label: { Label(item.sets.last?.plan.kind == .myoMini ? "Mini-set" : "Set", systemImage: "plus") }.buttonStyle(.bordered)
                        Button { technique = .drop } label: { Label("Drop", systemImage: "arrow.down.right") }.buttonStyle(.bordered).accessibilityIdentifier("workout.\(exerciseID).addDrop")
                        Button { technique = .myo } label: { Label("MYO", systemImage: "repeat") }.buttonStyle(.bordered).accessibilityIdentifier("workout.\(exerciseID).addMyo")
                    }.font(.subheadline)
                } else { Button { appendSet(item) } label: { Label("Add interval", systemImage: "plus") }.buttonStyle(.bordered) }
                Button { note.toggle() } label: { Label(item.notes.isEmpty ? "Note for today" : item.notes, systemImage: "note.text").font(.subheadline).multilineTextAlignment(.leading) }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Note for \(item.name): \(item.notes)").accessibilityIdentifier("workout.\(exerciseID).note")
                if note { TextField("Note for today", text: Binding(get: { self.item?.notes ?? "" }, set: { value in store.editExercise(exerciseID) { $0.notes = value } }), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...6).accessibilityIdentifier("workout.\(exerciseID).noteField") }
                }
            }.card()
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
            .confirmationDialog("Remove \(item.name)?", isPresented: $removing) { Button("Remove from workout", role: .destructive) { store.editActive { $0.exercises.removeAll { $0.id == exerciseID } } } } message: { Text("This removes its sets from the current workout.") }
        }
    }
    var completed: Bool { guard let item else { return false }; return !item.sets.isEmpty && item.sets.allSatisfy { $0.completedAt != nil } }
    var autoCollapseReady: Bool { completed && item?.collapsed != true && item?.keepExpanded != true && technique == nil && editVariant == nil && !substituting && !workingWeight && !note && store.data.settings.autoCollapseCompleted != false }
    func compactSummary(_ item: SessionExercise) -> String {
        let count = "\(item.sets.filter { $0.completedAt != nil }.count)/\(item.sets.count) sets"
        let best = item.sets.filter { $0.completedAt != nil }.max { ($0.weight ?? 0) < ($1.weight ?? 0) } ?? item.sets.first
        return [count, best.map { loggedSetSummary($0, unit: store.data.settings.unit) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
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
            Form {
                HStack { Text("Weight (\(store.data.settings.unit.rawValue))"); TextField("0", value: $weight, format: .number).multilineTextAlignment(.trailing) }
                Toggle("Save to this day variant", isOn: $future)
            }.formStyle(.grouped).navigationTitle("Working weight").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { store.perform { try $0.setWorkingWeight($0.settings.unit.kilograms(weight), for: exerciseID, saveFuture: future) }; dismiss() }.disabled(!weight.isFinite || weight < 0) }
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
