import SwiftUI
import LiftingCore

struct RoutineEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let routineID: UUID
    var showsStart = false
    @State private var picker = false
    @State private var dragging: UUID?
    @State private var expanded: UUID?
    @State private var linking = false
    @State private var linkedSlotID: UUID?
    @State private var warmups = false
    @State private var renaming = false
    @State private var name = ""
    private var routine: Routine? { store.data.routine(routineID) }

    var body: some View {
        ScrollView {
            if let routine {
                LazyVStack(alignment: .leading, spacing: 12) {
                    TextField("Day note", text: Binding(get: { self.routine?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                        .lineLimit(1...6).padding(16).card(padding: 0)
                    ForEach(routine.slots) { slot in
                        if let initial = store.data.variant(slot.variantID) {
                            TemplateExerciseCard(
                                variant: Binding(get: { store.data.variant(slot.variantID) ?? initial }, set: { _ = store.saveVariant($0) }),
                                expanded: expanded == slot.id,
                                groupTitle: groupTitle(slot, in: routine),
                                toggle: { withAnimation(.snappy) { expanded = expanded == slot.id ? nil : slot.id } },
                                link: { linkedSlotID = slot.id; linking = true },
                                move: { offset in move(slot.id, by: offset) },
                                canMoveUp: routine.slots.first?.id != slot.id,
                                canMoveDown: routine.slots.last?.id != slot.id,
                                slotID: slot.id, dragging: $dragging,
                                remove: { update { $0.slots.removeAll { $0.id == slot.id } } },
                                swap: { id in store.perform { try $0.swapSlotExercise(routineID: routineID, slotID: slot.id, to: id) } }
                            )
                            .modifier(ExerciseDropTarget(id: slot.id, dragging: $dragging) { source, target, after in
                                update { day in
                                    guard let from = day.slots.firstIndex(where: { $0.id == source }) else { return }
                                    let item = day.slots.remove(at: from)
                                    guard let to = day.slots.firstIndex(where: { $0.id == target }) else { day.slots.insert(item, at: from); return }
                                    day.slots.insert(item, at: to + (after ? 1 : 0))
                                }
                            })
                        }
                    }
                    Button { picker = true } label: { Label("Add Exercises", systemImage: "plus") }.buttonStyle(FieldButtonStyle()).accessibilityIdentifier("routine.addExercises")
                    if showsStart && !routine.slots.isEmpty { StartDayButton(day: routine) }
                }.padding(16)
            }
        }
        .background(palette.background).navigationTitle(routine?.name ?? "Day").inlineTitle()
        .toolbar {
            if let routine {
                ToolbarItem(placement: .primaryAction) {
                    DayMenu(day: routine, program: store.data.programForDay(routineID),
                            onDelete: { dismiss() }, onRename: { name = routine.name; renaming = true },
                            onWarmups: { warmups = true })
                }
            }
        }
        .alert("Rename Day", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") { update { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200)
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { if expanded == nil { expanded = routine?.slots.first?.id } }
        .sheet(isPresented: $picker) { ExercisePicker(title: "Add Exercises", onAdd: { store.add($0, to: routineID) }).sheetSize() }
        .sheet(isPresented: $linking) { LinkedExerciseEditor(routineID: routineID, exerciseID: linkedSlotID).sheetSize() }
        .sheet(isPresented: $warmups) { ApplyWarmupPreset(routineID: routineID).sheetSize() }
    }

    private func groupTitle(_ slot: RoutineSlot, in routine: Routine) -> String? {
        guard !slot.group.isEmpty else { return nil }
        let count = routine.slots.filter { $0.group == slot.group }.count
        return count > 1 ? (count > 2 ? "Circuit" : "Superset") : nil
    }

    private func update(_ change: (inout Routine) -> Void) {
        store.perform { data in
            guard let index = data.routines.firstIndex(where: { $0.id == routineID }) else { return }
            change(&data.routines[index])
        }
    }
    private func move(_ id: UUID, by offset: Int) {
        update { day in
            guard let index = day.slots.firstIndex(where: { $0.id == id }), day.slots.indices.contains(index + offset) else { return }
            day.slots.swapAt(index, index + offset)
        }
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
    var onAdd: (([Exercise]) -> Bool)? = nil
    @State private var selected: [UUID] = []
    @State private var search = ""
    @State private var mode = "All"
    @State private var future = false
    @State private var creating = false
    @State private var multiple = false
    @State private var committed = false
    var matches: [Exercise] {
        store.data.exercises.filter { (search.isEmpty || "\($0.name) \($0.muscle) \($0.equipment)".localizedCaseInsensitiveContains(search)) && (mode == "All" || $0.mode.title == mode) }.sorted {
            if similarMuscle != nil, ($0.muscle == similarMuscle) != ($1.muscle == similarMuscle) { return $0.muscle == similarMuscle }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Exercise, muscle, equipment", text: $search)
                        .textFieldStyle(.plain).accessibilityIdentifier("exercise.search")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.top, 8)
                Picker("Type", selection: $mode) { Text("All").tag("All"); ForEach(ExerciseMode.allCases) { Text($0.title).tag($0.title) } }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
            List {
                if substitution {
                    Section {
                        Picker("Scope", selection: $future) { Text("Today only").tag(false); Text("Future sessions").tag(true) }.pickerStyle(.segmented)
                    } footer: { Text(future ? "Future sessions of this day use the new exercise." : "The saved day stays unchanged.") }
                }
                ForEach(matches) { exercise in
                    Button {
                        choose(exercise)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.mode.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) { Text(exercise.name).foregroundStyle(.primary); Text([exercise.muscle, exercise.equipment].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if onAdd != nil && multiple {
                                Image(systemName: selected.contains(exercise.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(exercise.id) ? Color.accentColor : .secondary)
                            }
                            if exercise.muscle == similarMuscle { Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary) }
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(exercise.id) ? .isSelected : []).accessibilityIdentifier("exercise.pick.\(exercise.id)")
                }
                Button { creating = true } label: { Label(search.isEmpty ? "Create Exercise" : "Create \"\(search)\"", systemImage: "plus") }
            }.listStyle(.plain)
            }
            .navigationTitle(title).inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if let onAdd {
                    ToolbarItem(placement: .confirmationAction) {
                        if multiple {
                            Button("Add (\(selected.count))") {
                                guard !committed, onAdd(selected.compactMap { store.data.exercise($0) }) else { return }
                                committed = true; dismiss()
                            }.disabled(selected.isEmpty || committed).accessibilityIdentifier("exercise.addSelected")
                        } else {
                            Button("Select Multiple") { multiple = true }.accessibilityIdentifier("exercise.selectMultiple")
                        }
                    }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseEditor(initialName: search) { exercise in
                    guard store.perform({ $0.exercises.append(exercise) }) else { return false }
                    choose(exercise)
                    return true
                }.sheetSize()
            }
        }
    }
}

private extension ExercisePicker {
    func choose(_ exercise: Exercise) {
        guard !committed else { return }
        if let onAdd, !multiple {
            if onAdd([exercise]) { committed = true; dismiss() }
        } else if onAdd != nil {
            if let index = selected.firstIndex(of: exercise.id) { selected.remove(at: index) }
            else { selected.append(exercise.id) }
        } else {
            committed = true
            if substitution { onSubstitute?(exercise, future) } else { onSelect(exercise) }
            dismiss()
        }
    }
}

struct ExerciseEditor: View {
    @EnvironmentObject private var store: AppStore
    private let original: Exercise
    private let isNew: Bool
    private let onSave: (Exercise) -> Bool
    @State private var exercise: Exercise

    init(initialName: String = "", initialExercise: Exercise? = nil, onSave: @escaping (Exercise) -> Bool) {
        let value = initialExercise ?? Exercise(name: initialName)
        original = value; isNew = initialExercise == nil; self.onSave = onSave
        _exercise = State(initialValue: value)
    }
    private var valid: Bool {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 200
    }
    var body: some View {
        DraftEditor(valid: valid, changed: exercise != original, confirmation: isNew ? "Create" : nil, save: {
            var edited = exercise
            edited.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return onSave(edited)
        }) {
            ThemedForm {
                StoreErrorRow()
                Section {
                    TextField("Name", text: $exercise.name)
                    Picker("Type", selection: $exercise.mode) { ForEach(ExerciseMode.allCases) { Text($0.title).tag($0) } }
                    category("Equipment", kind: .equipment, value: $exercise.equipment, allowsEmpty: true)
                }
                Section("Muscles") {
                    category("Primary muscle", kind: .muscle, value: $exercise.muscle)
                    NavigationLink {
                        CategoryPicker(title: "Secondary Muscles", choices: ExerciseCategory.muscle.choices(in: catalog).filter { ExerciseCategory.key($0) != ExerciseCategory.key(exercise.muscle) }, selection: Binding(get: { exercise.secondaryMuscles ?? [] }, set: { exercise.secondaryMuscles = $0 }), multiple: true)
                    } label: { LabeledContent("Secondary muscles", value: (exercise.secondaryMuscles ?? []).isEmpty ? "None" : (exercise.secondaryMuscles ?? []).joined(separator: ", ")) }
                }
            }.formStyle(.grouped).navigationTitle(isNew ? "New Exercise" : "Edit Exercise").inlineTitle()
        }
    }
    private var catalog: [Exercise] { store.data.exercises + [exercise] }
    private func category(_ title: String, kind: ExerciseCategory, value: Binding<String>, allowsEmpty: Bool = false) -> some View {
        NavigationLink {
            CategoryPicker(title: title, choices: kind.choices(in: catalog), selection: Binding(get: { value.wrappedValue.isEmpty ? [] : [value.wrappedValue] }, set: { values in
                value.wrappedValue = values.first ?? ""
                if kind == .muscle { exercise.secondaryMuscles?.removeAll { ExerciseCategory.key($0) == ExerciseCategory.key(value.wrappedValue) } }
            }), allowsEmpty: allowsEmpty)
        } label: { LabeledContent(title, value: value.wrappedValue.isEmpty ? "None" : value.wrappedValue) }
    }
}
