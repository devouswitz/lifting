import SwiftUI
import LiftingCore

struct DayImportPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let programID: UUID
    @State private var selected: [UUID] = []

    var body: some View {
        NavigationStack {
            ThemedForm {
                ForEach(store.data.programs.filter { $0.id != programID }) { program in
                    Section(program.name) { ForEach(program.dayIDs.compactMap { store.data.routine($0) }) { day in row(day) } }
                }
                if !store.data.dayTemplates.isEmpty {
                    Section("Saved Days") { ForEach(store.data.dayTemplates) { day in row(day) } }
                }
            }.navigationTitle("Import Day").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import (\(selected.count))") {
                            if store.perform({ data in for id in selected { _ = try data.addDay(to: programID, templateID: id) } }) { dismiss() }
                        }.disabled(selected.isEmpty)
                    }
                }
        }
    }

    private func row(_ day: Routine) -> some View {
        Button {
            if let index = selected.firstIndex(of: day.id) { selected.remove(at: index) }
            else { selected.append(day.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.name).foregroundStyle(.primary)
                    Text(counted(day.slots.count, "exercise")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(day.id) ? "checkmark.circle.fill" : "circle")
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(day.id) ? .isSelected : [])
    }
}

struct SavedDaysView: View {
    @EnvironmentObject private var store: AppStore
    @State private var creating = false
    @State private var name = ""
    @State private var createdDay: UUID?
    @State private var deleting: Routine?
    var body: some View {
        ThemedForm {
            ForEach(store.data.dayTemplates) { day in
                NavigationLink { DayView(dayID: day.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.name)
                        Text(counted(day.slots.count, "exercise")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { deleting = day }
                    Button("Duplicate") { store.perform { _ = try $0.saveDayAsTemplate(day.id, name: TrainingData.uniqueName(day.name + " copy", among: $0.dayTemplates.map(\.name))) } }
                }
            }
            .onDelete { offsets in deleting = offsets.first.map { store.data.dayTemplates[$0] } }
            .onMove { source, destination in
                var ids = store.data.dayTemplates.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                store.perform { try $0.reorderTemplates(ids) }
            }
            AddRow(title: "New Saved Day") { name = ""; creating = true }
        }.navigationTitle("Saved Days")
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .navigationDestination(item: $createdDay) { RoutineEditor(routineID: $0) }
        .alert("New Saved Day", isPresented: $creating) {
            TextField("Name", text: $name)
            Button("Create") {
                let day = Routine(name: TrainingData.uniqueName(name.trimmingCharacters(in: .whitespacesAndNewlines), among: store.data.dayTemplates.map(\.name)))
                if store.perform({ $0.routines.append(day) }) { createdDay = day.id }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.name ?? "day")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Saved Day", role: .destructive) {
                if let deleting { store.perform { $0.removeDay(deleting.id) } }
                deleting = nil
            }
        }
    }
}
