import SwiftUI
import LiftingCore

struct RoutineEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let routineID: UUID
    @State private var picker = false
    @State private var editing: Variant?
    @State private var linking = false
    @State private var linkedSlotID: UUID?
    @State private var warmups = false
    #if os(iOS)
    @State private var reordering: EditMode = .inactive
    #endif
    var routine: Routine? { store.data.routines.first { $0.id == routineID } }
    func update(_ change: @escaping (inout Routine) -> Void) { store.perform { d in if let i = d.routines.firstIndex(where: { $0.id == routineID }) { change(&d.routines[i]) } } }
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            if let routine {
                EditableTitle(name: routine.name) { value in update { $0.name = value } }
                Section("Exercises") {
                    ForEach(routine.slots) { slot in
                        if let variant = store.data.variant(slot.variantID), let exercise = store.data.exercise(variant.exerciseID) {
                            Button { editing = variant } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(exercise.name).foregroundStyle(Color.primary).font(.headline)
                                        Text(planSummary(variant, unit: store.data.settings.unit)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                        HStack(spacing: 6) {
                                            if variant.label != defaultTrackName(routine) { Chip(title: variant.label) }
                                            if !slot.group.isEmpty, routine.slots.filter({ $0.group == slot.group }).count > 1 { Label(routine.slots.filter({ $0.group == slot.group }).count > 2 ? "Circuit" : "Superset", systemImage: "link").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 2).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Superset / Circuit", systemImage: "link") { linkedSlotID = slot.id; linking = true }
                                Button("Move Up", systemImage: "arrow.up") { update { r in if let i = r.slots.firstIndex(where: { $0.id == slot.id }), i > 0 { r.slots.swapAt(i, i - 1) } } }
                                Button("Move Down", systemImage: "arrow.down") { update { r in if let i = r.slots.firstIndex(where: { $0.id == slot.id }), i < r.slots.count - 1 { r.slots.swapAt(i, i + 1) } } }
                                Button("Remove", systemImage: "trash", role: .destructive) { update { $0.slots.removeAll { $0.id == slot.id } } }
                            }
                        }
                    }
                    .onMove { source, target in update { $0.slots.move(fromOffsets: source, toOffset: target) } }
                    .onDelete { offsets in update { $0.slots.remove(atOffsets: offsets) } }
                    Button { picker = true } label: { Label("Add Exercise", systemImage: "plus") }
                    if routine.slots.count > 1 { Button { linkedSlotID = nil; linking = true } label: { Label("Superset / Circuit", systemImage: "link") }.accessibilityIdentifier("routine.link") }
                    if !routine.slots.isEmpty { Button { warmups = true } label: { Label("Apply Warm-up Preset", systemImage: "flame") }.accessibilityIdentifier("routine.warmups") }
                }
                Section("Notes") {
                    TextField("Notes", text: Binding(get: { self.routine?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                }
            }
        }.formStyle(.grouped).titleInContent(routine?.name ?? "Day")
        .toolbar {
            #if os(iOS)
            if (routine?.slots.count ?? 0) > 1 || reordering == .active {
                Button(reordering == .active ? "Done" : "Reorder") { withAnimation { reordering = reordering == .active ? .inactive : .active } }.fontWeight(reordering == .active ? .semibold : .regular)
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $reordering)
        #endif
        .sheet(isPresented: $picker) { ExercisePicker(title: "Add Exercise") { store.add($0, to: routineID) }.environmentObject(store).sheetSize() }
        .sheet(item: $editing) { VariantEditor(variant: $0).environmentObject(store).sheetSize() }
        .sheet(isPresented: $linking) { LinkedExerciseEditor(routineID: routineID, exerciseID: linkedSlotID).environmentObject(store).sheetSize() }
        .sheet(isPresented: $warmups) { ApplyWarmupPreset(routineID: routineID).environmentObject(store).sheetSize() }
    }
}

extension RoutineEditor {
    /// The label new exercises get in this day; only differing labels are worth showing.
    func defaultTrackName(_ routine: Routine) -> String { [store.data.programForDay(routine.id)?.name, routine.name].compactMap { $0 }.joined(separator: " · ") }
}

struct ExercisePicker: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let title: String
    var similarMuscle: String? = nil
    var substitution = false
    var onSelect: (Exercise) -> Void = { _ in }
    var onSubstitute: ((Exercise, Bool) -> Void)? = nil
    @State private var search = ""
    @State private var mode = "All"
    @State private var future = false
    @State private var creating = false
    var matches: [Exercise] {
        store.data.exercises.filter { (search.isEmpty || "\($0.name) \($0.muscle) \($0.equipment)".localizedCaseInsensitiveContains(search)) && (mode == "All" || $0.mode.title == mode) }.sorted {
            if similarMuscle != nil, ($0.muscle == similarMuscle) != ($1.muscle == similarMuscle) { return $0.muscle == similarMuscle }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if substitution {
                    Section {
                        Picker("Scope", selection: $future) { Text("Today only").tag(false); Text("Future sessions").tag(true) }.pickerStyle(.segmented)
                    } footer: { Text(future ? "Future sessions of this day use the new exercise." : "The saved day stays unchanged.") }
                }
                Picker("Type", selection: $mode) { Text("All").tag("All"); ForEach(ExerciseMode.allCases) { Text($0.title).tag($0.title) } }.pickerStyle(.segmented)
                ForEach(matches) { exercise in
                    Button {
                        if substitution { onSubstitute?(exercise, future) } else { onSelect(exercise) }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.mode.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) { Text(exercise.name).foregroundStyle(.primary); Text([exercise.muscle, exercise.equipment].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if exercise.muscle == similarMuscle { Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary) }
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Button { creating = true } label: { Label(search.isEmpty ? "Create Exercise" : "Create \"\(search)\"", systemImage: "plus") }
            }.searchable(text: $search, prompt: "Exercise, muscle, equipment")
            .navigationTitle(title).inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $creating) {
                ExerciseEditor(initialName: search) { exercise in
                    store.perform { $0.exercises.append(exercise) }
                    if substitution { onSubstitute?(exercise, future) } else { onSelect(exercise) }
                    dismiss()
                }.sheetSize()
            }
        }
    }
}

struct ExerciseEditor: View {
    @Environment(\.dismiss) var dismiss
    var initialName = ""
    var initialExercise: Exercise? = nil
    var onSave: (Exercise) -> Void
    @State private var exercise = Exercise(name: "")
    var body: some View {
        NavigationStack {
            ThemedForm {
                StoreErrorRow()
                Section {
                    TextField("Name", text: $exercise.name)
                    Picker("Type", selection: $exercise.mode) { ForEach(ExerciseMode.allCases) { Text($0.title).tag($0) } }
                    TextField("Equipment", text: $exercise.equipment)
                }
                Section("Muscles") {
                    TextField("Primary muscle", text: $exercise.muscle)
                    TextField("Secondary muscles, comma separated", text: Binding(get: { exercise.secondaryMuscles?.joined(separator: ", ") ?? "" }, set: { exercise.secondaryMuscles = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                }
            }.formStyle(.grouped).navigationTitle(initialExercise == nil ? "New Exercise" : "Edit Exercise").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines); onSave(exercise); dismiss() }.disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.onAppear { if let initialExercise { exercise = initialExercise } else { exercise.name = initialName } }
    }
}
