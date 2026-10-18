import SwiftUI
import LiftingCore

struct TrainView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State private var library = false
    @State private var creatingProgram = false
    @State private var creatingTemplate = false
    @State private var templateName = ""
    @State private var importing = false
    @State private var export: CSVExportRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.demo { Chip(title: "Demo") }
                if let program = store.data.activeProgram {
                    HStack {
                        Menu {
                            ForEach(store.data.programs) { choice in
                                Button { store.perform { try $0.loadProgram(choice.id) } } label: {
                                    if choice.id == program.id { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                                }
                            }
                            Divider(); Button("All Programs") { library = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(program.name).font(.headline); Image(systemName: "chevron.down").font(.caption) }
                                Text(program.dayIDs.isEmpty ? "No days" : "Day \(program.nextDayIndex + 1) of \(program.dayIDs.count)").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("train.program")
                        NavigationLink { ProgramEditor(programID: program.id) } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("Edit program")
                    }.card()
                    if let next = program.nextDayID.flatMap(store.data.routine) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Next").font(.caption).foregroundStyle(.secondary)
                                    Text(next.name).font(.title2.weight(.semibold))
                                    Text(daySummary(next)).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    ForEach(program.dayIDs, id: \.self) { id in
                                        if let day = store.data.routine(id) { Button("Next: \(day.name)") { store.perform { try $0.selectNextDay(id, in: program.id) } } }
                                    }
                                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Choose next day")
                            }
                            Button { store.start(next) } label: { Text("Start \(next.name)").frame(maxWidth: .infinity) }.buttonStyle(AccentButtonStyle()).disabled(store.data.activeSession != nil).accessibilityIdentifier("train.startNext")
                        }.card()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Days").font(.headline)
                        ForEach(program.dayIDs, id: \.self) { id in if let day = store.data.routine(id) { dayRow(day, program: program) } }
                        NavigationLink { ProgramEditor(programID: program.id) } label: { Label("Add or reorder days", systemImage: "plus").font(.subheadline).padding(.vertical, 6) }
                    }
                } else {
                    Button { library = true } label: { Label("Load Program", systemImage: "square.stack").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Templates").font(.headline)
                    ForEach(store.data.dayTemplates) { day in dayRow(day, program: nil) }
                    Button { templateName = ""; creatingTemplate = true } label: { Label("New Template", systemImage: "plus").font(.subheadline).padding(.vertical, 6) }
                }
                Button("Empty Workout", action: store.emptyWorkout).buttonStyle(.bordered).disabled(store.data.activeSession != nil)
            }.padding(16)
        }.background(Palette.background(scheme)).navigationTitle("Train")
        .toolbar { ToolbarItem(placement: .primaryAction) { Menu {
            Button("New Program", systemImage: "square.stack") { creatingProgram = true }
            Button("New Template", systemImage: "plus") { templateName = ""; creatingTemplate = true }
            Button("Import CSV", systemImage: "square.and.arrow.down") { importing = true }
        } label: { Image(systemName: "plus").frame(width: 36, height: 36) }.accessibilityLabel("Add or import").accessibilityIdentifier("train.add") } }
        .sheet(isPresented: $library) { ProgramLibrary().environmentObject(store).sheetSize() }
        .sheet(isPresented: $creatingProgram) { NewProgramView().environmentObject(store).sheetSize() }
        .alert("New Template", isPresented: $creatingTemplate) {
            TextField("Name", text: $templateName)
            Button("Create") { let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { store.perform { $0.routines.append(Routine(name: TrainingData.uniqueName(name, among: $0.dayTemplates.map(\.name)))) } } }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(CSVImportModifier(isPresented: $importing)).modifier(CSVExportModifier(request: $export))
    }
    func daySummary(_ day: Routine) -> String {
        let sets = day.slots.reduce(0) { $0 + (store.data.variant($1.variantID)?.sets.count ?? 0) }
        return "\(counted(day.slots.count, "exercise")) · \(counted(sets, "set"))"
    }
    func dayRow(_ day: Routine, program: TrainingProgram?) -> some View {
        HStack(spacing: 12) {
            NavigationLink { RoutineEditor(routineID: day.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(day.name).font(.headline); if program?.nextDayID == day.id { Chip(title: "Next") } }
                    Text(daySummary(day)).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { store.start(day) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Start \(day.name)").disabled(store.data.activeSession != nil)
        }.card()
        .contextMenu {
            Button("Start") { store.start(day) }.disabled(store.data.activeSession != nil)
            if let program {
                Button("Set as Next") { store.perform { try $0.selectNextDay(day.id, in: program.id) } }
                Button("Duplicate Day") { store.perform { _ = try $0.addDay(to: program.id, templateID: day.id, name: TrainingData.uniqueName(day.name + " copy", among: program.dayIDs.compactMap { store.data.routine($0)?.name })) } }
                Button("Save as Template") { store.perform { _ = try $0.saveDayAsTemplate(day.id) } }
            } else {
                if !store.data.programs.isEmpty { Menu("Add to Program") { ForEach(store.data.programs) { target in Button(target.name) { store.perform { _ = try $0.addDay(to: target.id, templateID: day.id) } } } } }
                Button("Duplicate Template") { store.perform { _ = try $0.saveDayAsTemplate(day.id, name: day.name + " copy") } }
            }
            Button("Export CSV") { do { export = try .day(day.id, in: store.data) } catch { store.error = error.localizedDescription } }
        }
    }
}
