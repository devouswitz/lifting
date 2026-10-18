import SwiftUI
import LiftingCore

struct ProgramLibrary: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var creating = false
    @State private var importing = false
    var body: some View {
        NavigationStack {
            List {
                StoreErrorRow()
                ForEach(store.data.programs) { program in
                    HStack {
                        NavigationLink { ProgramEditor(programID: program.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(program.name).font(.headline)
                                Text(counted(program.dayIDs.count, "day")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 12)
                        if program.id == store.data.activeProgramID { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Loaded") }
                        else { Button("Load") { if store.perform({ try $0.loadProgram(program.id) }) { dismiss() } }.buttonStyle(.bordered) }
                    }.contextMenu {
                        Button("Move up") { moveProgram(program.id, by: -1) }
                        Button("Move down") { moveProgram(program.id, by: 1) }
                    }
                }.onMove { source, target in store.perform { $0.programs.move(fromOffsets: source, toOffset: target) } }
                Button("New Program", systemImage: "plus") { creating = true }
                Button("Import CSV", systemImage: "square.and.arrow.down") { importing = true }
            }.navigationTitle("Programs").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
                #endif
            }
            .sheet(isPresented: $creating) { NewProgramView().environmentObject(store).sheetSize() }
            .modifier(CSVImportModifier(isPresented: $importing))
        }
    }
    func moveProgram(_ id: UUID, by offset: Int) {
        store.perform { d in guard let i = d.programs.firstIndex(where: { $0.id == id }), d.programs.indices.contains(i + offset) else { return }; d.programs.swapAt(i, i + offset) }
    }

}

struct NewProgramView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    var clean: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                StoreErrorRow()
                Section { TextField("Program name", text: $name).accessibilityIdentifier("program.name") }
                Section("Add Templates") {
                    ForEach(store.data.dayTemplates) { day in
                        Toggle(day.name, isOn: Binding(get: { selected.contains(day.id) }, set: { if $0 { selected.insert(day.id) } else { selected.remove(day.id) } }))
                    }
                }
            }.formStyle(.grouped).navigationTitle("New Program").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create and Load") {
                    if store.perform({ d in let id = try d.createProgram(name: clean, templateIDs: d.dayTemplates.filter { selected.contains($0.id) }.map(\.id)); try d.loadProgram(id) }) { dismiss() }
                }.disabled(clean.isEmpty || clean.count > 200).accessibilityIdentifier("program.create") }
            }
        }
    }
}

struct ProgramEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let programID: UUID
    @State private var addingBlank = false
    @State private var dayName = ""
    @State private var deleting = false
    @State private var export: CSVExportRequest?
    var program: TrainingProgram? { store.data.program(programID) }
    func update(_ change: @escaping (inout TrainingProgram) -> Void) { store.perform { d in if let i = d.programs.firstIndex(where: { $0.id == programID }) { change(&d.programs[i]) } } }
    var body: some View {
        Form {
            StoreErrorRow()
            if let program {
                Section("Program") {
                    SavedNameField(name: program.name) { value in update { $0.name = value } }
                    TextField("Notes", text: Binding(get: { self.program?.notes ?? "" }, set: { value in update { $0.notes = value } }), axis: .vertical)
                    if store.data.activeProgramID == programID { Label("Loaded", systemImage: "checkmark").foregroundStyle(.secondary) }
                    else { Button("Load Program") { store.perform { try $0.loadProgram(programID) } }.accessibilityIdentifier("program.load") }
                }
                Section("Days") {
                    ForEach(program.dayIDs, id: \.self) { id in
                        if let day = store.data.routine(id) {
                            NavigationLink { RoutineEditor(routineID: id) } label: { HStack { Text(day.name); Spacer(); if program.nextDayID == id { Chip(title: "Next") } } }
                                .contextMenu {
                                    Button("Set as Next") { store.perform { try $0.selectNextDay(id, in: programID) } }
                                    Button("Move up") { move(id, by: -1) }
                                    Button("Move down") { move(id, by: 1) }
                                    Button("Save as Template") { store.perform { _ = try $0.saveDayAsTemplate(id) } }
                                    Button("Remove Day", role: .destructive) { store.perform { $0.removeDay(id) } }
                                }
                        }
                    }.onMove { source, target in var ids = program.dayIDs; ids.move(fromOffsets: source, toOffset: target); store.perform { try $0.reorderDays(ids, in: programID) } }
                    .onDelete { offsets in let ids = offsets.map { program.dayIDs[$0] }; store.perform { d in for id in ids { d.removeDay(id) } } }
                    Menu {
                        Button("Blank Day") { dayName = ""; addingBlank = true }
                        if !store.data.dayTemplates.isEmpty { Menu("From Template") { ForEach(store.data.dayTemplates) { day in Button(day.name) { store.perform { _ = try $0.addDay(to: programID, templateID: day.id) } } } } }
                    } label: { Label("Add Day", systemImage: "plus") }.accessibilityIdentifier("program.addDay")
                }
                Section {
                    Button("Export CSV") { do { export = try .program(programID, in: store.data) } catch { store.error = error.localizedDescription } }
                    Button("Duplicate Program") { store.perform { _ = try $0.duplicateProgram(programID) } }
                    Button("Delete Program", role: .destructive) { deleting = true }
                }
            }
        }.formStyle(.grouped).navigationTitle(program?.name ?? "Program").inlineTitle()
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .alert("New Day", isPresented: $addingBlank) {
            TextField("Name", text: $dayName)
            Button("Add") { let clean = dayName.trimmingCharacters(in: .whitespacesAndNewlines); if !clean.isEmpty { store.perform { _ = try $0.addDay(to: programID, name: clean) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete program and its days?", isPresented: $deleting) { Button("Delete Program", role: .destructive) { if store.perform({ $0.removeProgram(programID) }) { dismiss() } } } message: { Text("Templates and workout history are kept.") }
        .modifier(CSVExportModifier(request: $export))
    }
    func move(_ id: UUID, by offset: Int) {
        guard var ids = program?.dayIDs, let i = ids.firstIndex(of: id), ids.indices.contains(i + offset) else { return }
        ids.swapAt(i, i + offset); store.perform { try $0.reorderDays(ids, in: programID) }
    }
}
