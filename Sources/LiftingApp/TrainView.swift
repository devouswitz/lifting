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
    @State private var section = 0
    @State private var deleting: Routine?
    @State private var createdID: UUID?
    @State private var editingCreated = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Library", selection: $section) {
                    Text("Program").tag(0)
                    Text("Templates").tag(1)
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("train.library")
                if section == 0 {
                    programHeader
                    if let program = store.data.activeProgram {
                        ForEach(program.dayIDs, id: \.self) { id in
                            if let day = store.data.routine(id) { dayCard(day, program: program) }
                        }
                        if program.dayIDs.isEmpty {
                            NavigationLink { ProgramEditor(programID: program.id) } label: { Label("Add Day", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
                        }
                    } else {
                        Button("Create Program") { creatingProgram = true }.buttonStyle(AccentButtonStyle())
                    }
                } else {
                    ForEach(store.data.dayTemplates) { day in dayCard(day, program: nil) }
                    Button { templateName = ""; creatingTemplate = true } label: { Label("New Template", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
                }
            }.padding(16)
        }
        .background(Palette.background(scheme)).navigationTitle("Workout")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Empty Workout", systemImage: "play") { store.emptyWorkout() }.disabled(store.data.activeSession != nil)
                    Divider()
                    Button("New Program", systemImage: "folder.badge.plus") { creatingProgram = true }
                    Button("New Template", systemImage: "plus") { templateName = ""; creatingTemplate = true }
                    Button("Import CSV", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus").frame(width: 32, height: 32) }.compactMenu().accessibilityLabel("New workout or template").accessibilityIdentifier("train.add")
            }
        }
        .sheet(isPresented: $library) { ProgramLibrary().environmentObject(store).sheetSize() }
        .sheet(isPresented: $creatingProgram) { NewProgramView().environmentObject(store).sheetSize() }
        .navigationDestination(isPresented: $editingCreated) { if let createdID { RoutineEditor(routineID: createdID) } }
        .alert("New Template", isPresented: $creatingTemplate) {
            TextField("Name", text: $templateName)
            Button("Create") {
                let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                let day = Routine(name: TrainingData.uniqueName(name, among: store.data.dayTemplates.map(\.name)))
                if !name.isEmpty, store.perform({ $0.routines.append(day) }) { createdID = day.id; editingCreated = true }
            }.disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || templateName.count > 200)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this day?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { store.perform { $0.removeDay(deleting.id) } }; deleting = nil }
        } message: { Text("Workout history is kept.") }
        .modifier(CSVImportModifier(isPresented: $importing)).modifier(CSVExportModifier(request: $export))
    }

    var programHeader: some View {
        HStack {
            Menu {
                ForEach(store.data.programs) { program in
                    Button { store.perform { try $0.loadProgram(program.id) } } label: {
                        if store.data.activeProgramID == program.id { Label(program.name, systemImage: "checkmark") }
                        else { Text(program.name) }
                    }.accessibilityIdentifier("program.select.\(program.id)")
                }
                Divider()
                Button("Programs") { library = true }
            } label: {
                HStack(spacing: 7) { Text(store.data.activeProgram?.name ?? "Select Program").font(.headline); Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
            }.compactMenu().accessibilityIdentifier("train.program")
            Spacer()
            if let program = store.data.activeProgram {
                NavigationLink { ProgramEditor(programID: program.id) } label: { Image(systemName: "folder").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("Manage program")
            } else {
                Button { library = true } label: { Image(systemName: "folder").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("Programs")
            }
        }.padding(.horizontal, 2)
    }

    func dayCard(_ day: Routine, program: TrainingProgram?) -> some View {
        let next = program?.nextDayID == day.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NavigationLink { RoutineEditor(routineID: day.id) } label: {
                    HStack(spacing: 8) {
                        Text(day.name).font(.headline)
                        if next { Text("Next").font(.caption.weight(.medium)).foregroundStyle(Palette.tint(scheme)) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !next {
                    Button { store.start(day) } label: { Image(systemName: "play.fill").frame(width: 32, height: 32) }.buttonStyle(.plain).foregroundStyle(Palette.tint(scheme)).disabled(store.data.activeSession != nil).accessibilityLabel("Start \(day.name)")
                }
                Menu { dayActions(day, program: program) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 32) }.compactMenu().accessibilityLabel("Options for \(day.name)")
            }
            if next {
                VStack(spacing: 9) {
                    ForEach(day.slots) { slot in
                        if let variant = store.data.variant(slot.variantID), let exercise = store.data.exercise(variant.exerciseID) {
                            HStack(spacing: 8) {
                                Text(exercise.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                                Text(target(variant)).foregroundStyle(.secondary).monospacedDigit()
                                if exercise.mode == .strength { Text("\(number(store.data.settings.unit.display(variant.workingWeight))) \(store.data.settings.unit.rawValue)").foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 58, alignment: .trailing) }
                            }.font(.subheadline)
                        }
                    }
                }
                Button { store.start(day) } label: { Text("Start Workout").frame(maxWidth: .infinity, minHeight: 24) }.buttonStyle(AccentButtonStyle()).disabled(store.data.activeSession != nil || day.slots.isEmpty).accessibilityIdentifier("train.startNext")
            } else {
                Text(day.slots.compactMap { store.data.variant($0.variantID).flatMap { store.data.exercise($0.exerciseID)?.name } }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(14).background(Palette.surface(scheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder func dayActions(_ day: Routine, program: TrainingProgram?) -> some View {
        NavigationLink("Edit") { RoutineEditor(routineID: day.id) }
        if let program {
            Button("Set as Next") { store.perform { try $0.selectNextDay(day.id, in: program.id) } }
            Button("Move up") { moveDay(day.id, in: program, by: -1) }
            Button("Move down") { moveDay(day.id, in: program, by: 1) }
            Divider()
            Button("Save as Template") { store.perform { _ = try $0.saveDayAsTemplate(day.id) } }
            Button("Duplicate Day") { store.perform { _ = try $0.addDay(to: program.id, templateID: day.id, name: TrainingData.uniqueName(day.name + " copy", among: store.data.routines.map(\.name))) } }
        } else {
            if !store.data.programs.isEmpty {
                Menu("Add to Program") { ForEach(store.data.programs) { target in Button(target.name) { store.perform { _ = try $0.addDay(to: target.id, templateID: day.id) } } } }
            }
            Button("Duplicate Template") { store.perform { _ = try $0.saveDayAsTemplate(day.id, name: day.name + " copy") } }
        }
        Button("Export CSV") { do { export = try .day(day.id, in: store.data) } catch { store.error = error.localizedDescription } }
        Button("Delete", role: .destructive) { deleting = day }
    }
    func moveDay(_ id: UUID, in program: TrainingProgram, by delta: Int) {
        var ids = program.dayIDs
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return }
        ids.swapAt(index, index + delta); store.perform { try $0.reorderDays(ids, in: program.id) }
    }
    func target(_ variant: Variant) -> String {
        let work = variant.sets.filter { $0.kind != .warmup }
        guard let plan = work.first else { return "" }
        if let seconds = plan.seconds { return clockText(seconds) }
        if let reps = plan.reps { return "\(work.count) × \(reps)\(plan.repCeiling.map { $0 != reps ? "-\($0)" : "" } ?? "")" }
        return counted(work.count, "set")
    }
}
