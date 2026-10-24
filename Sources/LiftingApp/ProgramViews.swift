import SwiftUI
import LiftingCore

/// All programs and day templates. Tap a program to load it; the info button opens it.
struct ProgramsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    #if os(iOS)
    @State private var editMode = EditMode.inactive
    #endif
    private var isEditing: Bool {
        #if os(iOS)
        editMode == .active
        #else
        false
        #endif
    }
    @State private var creatingProgram = false
    @State private var importing = false
    @State private var detail: UUID?
    @State private var deleting: TrainingProgram?
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            Section {
                ForEach(store.data.programs) { program in
                    HStack(spacing: 12) {
                        Button { store.perform { try $0.loadProgram(program.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(palette.action)
                                    .opacity(program.id == store.data.activeProgramID ? 1 : 0).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.name).foregroundStyle(.primary)
                                    Text(counted(program.dayIDs.count, "day")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel("\(program.name), \(counted(program.dayIDs.count, "day"))").accessibilityAddTraits(program.id == store.data.activeProgramID ? .isSelected : [])
                        Button { detail = program.id } label: { Image(systemName: "info.circle").font(.title3).foregroundStyle(palette.action) }
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .buttonStyle(.borderless).accessibilityLabel("Open \(program.name)").accessibilityIdentifier("programs.info.\(program.id)")
                    }
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { store.perform { _ = try $0.duplicateProgram(program.id) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = program }
                    }
                }
                .onMove { source, target in store.perform { $0.programs.move(fromOffsets: source, toOffset: target) } }
                AddRow(title: "New Program") { creatingProgram = true }.accessibilityIdentifier("programs.new")
            }
            Section {
                NavigationLink { SavedDaysView() } label: { Label("Saved Days", systemImage: "doc.on.doc") }
                NavigationLink { ExerciseLibraryView() } label: {
                    HStack { Label("Exercises", systemImage: "dumbbell"); Spacer(); Text("\(store.data.exercises.count)").foregroundStyle(.secondary).monospacedDigit() }
                }.accessibilityIdentifier("programs.exercises")
                AddRow(title: "Import from CSV", symbol: "square.and.arrow.down") { importing = true }
            }
        }
        .formStyle(.grouped).navigationTitle("Programs")
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) { if store.data.programs.count > 1 || isEditing { Button(isEditing ? "Done" : "Reorder") { withAnimation { editMode = isEditing ? .inactive : .active } } } }
            #endif
        }
        .navigationDestination(item: $detail) { ProgramEditor(programID: $0) }
        .sheet(isPresented: $creatingProgram) { NewProgramView().environmentObject(store).sheetSize() }
        .alert("Delete \(deleting?.name ?? "program")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete Program", role: .destructive) { if let deleting { store.perform { $0.removeProgram(deleting.id) } }; deleting = nil }
        } message: { Text("Its days will be removed. Saved days and workout history are kept.") }
        .modifier(CSVImportModifier(isPresented: $importing))
    }
}

/// Every exercise, with New Exercise and editing for ones not yet logged.
struct ExerciseLibraryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @State private var search = ""
    @State private var creating = false
    @State private var editing: Exercise?
    private var matches: [Exercise] {
        store.data.exercises.filter { search.isEmpty || "\($0.name) \($0.muscle) \($0.equipment)".localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            Section { AddRow(title: "New Exercise") { creating = true }.accessibilityIdentifier("exercises.new") }
            Section {
                if matches.isEmpty { Text("No matching exercises").foregroundStyle(.secondary) }
                ForEach(matches) { exercise in
                    Button { editing = exercise } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.mode.symbol).foregroundStyle(.secondary).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).foregroundStyle(Color.primary)
                                let detail = [exercise.muscle, exercise.equipment].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint("Edit exercise")
                }
            }
        }
        .formStyle(.grouped).navigationTitle("Exercises")
        .searchable(text: $search, prompt: "Exercise, muscle, equipment")
        .sheet(isPresented: $creating) {
            ExerciseEditor(initialName: search) { exercise in store.perform { $0.exercises.append(exercise) } }.environmentObject(store).sheetSize()
        }
        .sheet(item: $editing) { exercise in
            ExerciseEditor(initialExercise: exercise) { value in
                store.perform { data in if let index = data.exercises.firstIndex(where: { $0.id == value.id }) { data.exercises[index] = value } }
            }.environmentObject(store).sheetSize()
        }
    }
}

struct NewProgramView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    var clean: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            ThemedForm {
                StoreErrorRow()
                Section { TextField("Program name", text: $name).accessibilityIdentifier("program.name") }
                if !store.data.dayTemplates.isEmpty {
                    Section {
                        DisclosureGroup("Start with Saved Days") {
                            ForEach(store.data.dayTemplates) { day in
                                Button {
                                    if selected.contains(day.id) { selected.remove(day.id) } else { selected.insert(day.id) }
                                } label: {
                                    HStack { Text(day.name).foregroundStyle(.primary); Spacer(); if selected.contains(day.id) { Image(systemName: "checkmark") } }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(day.id) ? .isSelected : [])
                            }
                        }
                    }
                }
            }.formStyle(.grouped).navigationTitle("New Program").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") {
                    if store.perform({ d in let id = try d.createProgram(name: clean, templateIDs: d.dayTemplates.filter { selected.contains($0.id) }.map(\.id)); try d.loadProgram(id) }) { dismiss() }
                }.disabled(clean.isEmpty || clean.count > 200).accessibilityIdentifier("program.create") }
            }
        }
    }
}

struct ProgramEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    let programID: UUID
    @State private var addingBlank = false
    @State private var importingDay = false
    @State private var newDay: UUID?
    @State private var dayName = ""
    @State private var deleting = false
    @State private var export: CSVExportRequest?
    var program: TrainingProgram? { store.data.program(programID) }
    func update(_ change: @escaping (inout TrainingProgram) -> Void) { store.perform { d in if let i = d.programs.firstIndex(where: { $0.id == programID }) { change(&d.programs[i]) } } }
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            if let program {
                EditableTitle(name: program.name) { value in update { $0.name = value } }
                Section {
                    ForEach(Array(program.dayIDs.enumerated()), id: \.element) { index, id in
                        if let day = store.data.routine(id) {
                            NavigationLink { DayView(dayID: id) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(day.name)
                                        Text(counted(day.slots.count, "exercise")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if program.nextDayID == id { Chip(title: "Next", accent: true) }
                                }
                            }
                            .modifier(ReorderActions(canMoveUp: index > 0, canMoveDown: index + 1 < program.dayIDs.count) { move(id, by: $0) })
                            .swipeActions(edge: .leading) {
                                if program.nextDayID != id { Button("Make Next") { store.perform { try $0.selectNextDay(id, in: programID) } }.tint(palette.action) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { store.perform { $0.removeDay(id) } }.tint(.red)
                            }
                        }
                    }
                    .onMove { source, target in var ids = program.dayIDs; ids.move(fromOffsets: source, toOffset: target); store.perform { try $0.reorderDays(ids, in: programID) } }
                    AddRow(title: "Add Day") { dayName = ""; addingBlank = true }.accessibilityIdentifier("program.addDay")
                    AddRow(title: "Import Day", symbol: "square.and.arrow.down") { importingDay = true }.accessibilityIdentifier("program.importDay")
                } header: { Text("Days") }
                Section("Notes") {
                    TextField("Notes", text: Binding(get: { self.program?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                }
                Section {
                    if store.data.activeProgramID == programID { Label("Current program", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary) }
                    else { AddRow(title: "Make Current Program", symbol: "checkmark.circle") { store.perform { try $0.loadProgram(programID) } }.accessibilityIdentifier("program.load") }
                    AddRow(title: "Duplicate Program", symbol: "plus.square.on.square") { store.perform { _ = try $0.duplicateProgram(programID) } }
                    AddRow(title: "Export CSV", symbol: "square.and.arrow.up") { do { export = try .program(programID, in: store.data) } catch { store.error = error.localizedDescription } }
                }
                Section { Button("Delete Program", role: .destructive) { deleting = true } }
            }
        }.formStyle(.grouped).titleInContent(program?.name ?? "Program")
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .navigationDestination(item: $newDay) { RoutineEditor(routineID: $0) }
        .sheet(isPresented: $importingDay) { DayImportPicker(programID: programID).sheetSize() }
        .alert("New Day", isPresented: $addingBlank) {
            TextField("Name", text: $dayName)
            Button("Add") { let clean = dayName.trimmingCharacters(in: .whitespacesAndNewlines); if !clean.isEmpty { store.perform { newDay = try $0.addDay(to: programID, name: clean) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete program and its days?", isPresented: $deleting) { Button("Cancel", role: .cancel) {} ; Button("Delete Program", role: .destructive) { if store.perform({ $0.removeProgram(programID) }) { dismiss() } } } message: { Text("Templates and workout history are kept.") }
        .modifier(CSVExportModifier(request: $export))
    }
    func move(_ id: UUID, by offset: Int) {
        guard var ids = program?.dayIDs, let i = ids.firstIndex(of: id), ids.indices.contains(i + offset) else { return }
        ids.swapAt(i, i + offset); store.perform { try $0.reorderDays(ids, in: programID) }
    }
}
