import SwiftUI
import LiftingCore

struct RoutineEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let routineID: UUID
    @State private var picker = false
    @State private var editing: Variant?
    @State private var deleting = false
    @State private var export: CSVExportRequest?
    var isTemplate: Bool { store.data.programForDay(routineID) == nil }
    var routine: Routine? { store.data.routines.first { $0.id == routineID } }
    func update(_ change: @escaping (inout Routine) -> Void) { store.perform { d in if let i = d.routines.firstIndex(where: { $0.id == routineID }) { change(&d.routines[i]) } } }
    var body: some View {
        Form {
            StoreErrorRow()
            if let routine {
                Section(isTemplate ? "Template" : "Day") {
                    SavedNameField(name: routine.name) { value in update { $0.name = value } }
                    TextField("Notes", text: Binding(get: { self.routine?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                }
                Section("Exercises") {
                    ForEach(routine.slots) { slot in
                        if let variant = store.data.variant(slot.variantID), let exercise = store.data.exercise(variant.exerciseID) {
                            Button { editing = variant } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(exercise.name).foregroundStyle(.primary).font(.headline)
                                        Text(planSummary(variant, unit: store.data.settings.unit)).font(.subheadline).foregroundStyle(.secondary)
                                        Chip(title: variant.label)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Move up") { update { r in if let i = r.slots.firstIndex(where: { $0.id == slot.id }), i > 0 { r.slots.swapAt(i, i - 1) } } }
                                Button("Move down") { update { r in if let i = r.slots.firstIndex(where: { $0.id == slot.id }), i < r.slots.count - 1 { r.slots.swapAt(i, i + 1) } } }
                                Button("Remove", role: .destructive) { update { $0.slots.removeAll { $0.id == slot.id } } }
                            }
                        }
                    }
                    .onMove { source, target in update { $0.slots.move(fromOffsets: source, toOffset: target) } }
                    .onDelete { offsets in update { $0.slots.remove(atOffsets: offsets) } }
                    Button { picker = true } label: { Label("Add exercise", systemImage: "plus") }
                }
                Section {
                    Button("Export CSV") { do { export = try .day(routineID, in: store.data) } catch { store.error = error.localizedDescription } }
                    if let program = store.data.programForDay(routineID) {
                        Button("Save as Template") { store.perform { _ = try $0.saveDayAsTemplate(routineID) } }
                        Button("Duplicate Day") { store.perform { _ = try $0.addDay(to: program.id, templateID: routineID, name: TrainingData.uniqueName(routine.name + " copy", among: store.data.routines.map(\.name))) } }
                    } else {
                        if !store.data.programs.isEmpty { Menu("Add to Program") { ForEach(store.data.programs) { program in Button(program.name) { store.perform { _ = try $0.addDay(to: program.id, templateID: routineID) } } } } }
                        Button("Duplicate Template") { store.perform { _ = try $0.saveDayAsTemplate(routineID, name: TrainingData.uniqueName(routine.name + " copy", among: store.data.routines.map(\.name))) } }
                    }
                    Button(isTemplate ? "Delete Template" : "Delete Day", role: .destructive) { deleting = true }
                }
            }
        }.formStyle(.grouped).navigationTitle(routine?.name ?? "Day").inlineTitle()
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .sheet(isPresented: $picker) { ExercisePicker(title: "Add exercise") { store.add($0, to: routineID) }.environmentObject(store).sheetSize() }
        .sheet(item: $editing) { VariantEditor(variant: $0).environmentObject(store).sheetSize() }
        .modifier(CSVExportModifier(request: $export))
        .confirmationDialog(isTemplate ? "Delete template?" : "Delete day?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { if store.perform({ $0.removeDay(routineID) }) { dismiss() } }
        } message: { Text("Workout history is kept.") }
    }
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
                    } footer: { Text(future ? "Changes this routine slot only." : "Your routine stays unchanged.") }
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
                Button { creating = true } label: { Label(search.isEmpty ? "Create exercise" : "Create \"\(search)\"", systemImage: "plus") }
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
            Form {
                StoreErrorRow()
                TextField("Name", text: $exercise.name)
                Picker("Tracking", selection: $exercise.mode) { ForEach(ExerciseMode.allCases) { Text($0.title).tag($0) } }
                TextField("Muscle group", text: $exercise.muscle)
                TextField("Equipment", text: $exercise.equipment)
            }.formStyle(.grouped).navigationTitle(initialExercise == nil ? "New exercise" : "Edit exercise").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines); onSave(exercise); dismiss() }.disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.onAppear { if let initialExercise { exercise = initialExercise } else { exercise.name = initialName } }
    }
}
