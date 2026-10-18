import SwiftUI
import UniformTypeIdentifiers
import LiftingCore

struct CSVExportRequest {
    var bytes: Data
    var name: String
    static func day(_ id: UUID, in data: TrainingData) throws -> Self {
        Self(bytes: try RoutineCSV.export(data, dayID: id), name: data.routine(id)?.name ?? "Day")
    }
    static func program(_ id: UUID, in data: TrainingData) throws -> Self {
        Self(bytes: try RoutineCSV.export(data, programID: id), name: data.program(id)?.name ?? "Program")
    }
}

struct CSVExportModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @Binding var request: CSVExportRequest?
    func body(content: Content) -> some View {
        content.fileExporter(isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }), document: BackupDocument(bytes: request?.bytes ?? Data()), contentType: .commaSeparatedText, defaultFilename: safeName(request?.name ?? "Lifting")) { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
            request = nil
        }
    }
    func safeName(_ value: String) -> String {
        String(value.map { "/\\:\n\r".contains($0) ? "-" : $0 }.prefix(100))
    }
}

private struct CSVPreview: Identifiable {
    var id = UUID()
    var routines: RoutineBundle?
    var history: HistoryBundle?
}

struct CSVImportModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @Binding var isPresented: Bool
    @State private var preview: CSVPreview?
    func body(content: Content) -> some View {
        content.background {
        Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        .fileImporter(isPresented: $isPresented, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25_000_000 else { throw TrainingError.invalid("CSV files must be under 25 MB.") }
                let bytes = try Data(contentsOf: url)
                let header = try CSVCodec.parse(bytes)[0].map { $0.lowercased().replacingOccurrences(of: " ", with: "_").trimmingCharacters(in: .whitespacesAndNewlines) }
                if header.contains("day") { preview = CSVPreview(routines: try RoutineCSV.decode(bytes)) }
                else { preview = CSVPreview(history: try HistoryCSV.decode(bytes)) }
            } catch { store.error = "Import failed. \(error.localizedDescription)" }
        }
        .sheet(item: $preview) { item in CSVImportPreview(routines: item.routines, history: item.history).environmentObject(store).sheetSize() }
        }
    }
}

private struct CSVImportPreview: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var routines: RoutineBundle?
    var history: HistoryBundle?
    var body: some View {
        NavigationStack {
            Form {
                StoreErrorRow()
                if let bundle = routines {
                    Section {
                        if !bundle.content.programs.isEmpty { LabeledContent("Programs", value: "\(bundle.content.programs.count)") }
                        LabeledContent("Days", value: "\(bundle.dayCount)")
                        LabeledContent("Sets", value: "\(bundle.setCount)")
                    } footer: { Text("Adds independent copies. Existing programs and history stay unchanged.") }
                    ForEach(bundle.content.programs) { program in
                        Section(program.name) {
                            ForEach(program.dayIDs, id: \.self) { id in if let day = bundle.content.routine(id) { dayPreview(day, in: bundle.content) } }
                        }
                    }
                    if !bundle.content.dayTemplates.isEmpty {
                        Section("Templates") { ForEach(bundle.content.dayTemplates) { day in dayPreview(day, in: bundle.content) } }
                    }
                    Section {
                        Button(bundle.content.programs.isEmpty ? "Add to Templates" : "Add") { add(bundle, load: false) }.accessibilityIdentifier("csv.add")
                        if !bundle.content.programs.isEmpty { Button("Add and Load") { add(bundle, load: true) }.accessibilityIdentifier("csv.addAndLoad") }
                    }
                }
                if let bundle = history {
                    let existing = Set(store.data.sessions.map(\.id))
                    let count = bundle.content.sessions.filter { !existing.contains($0.id) }.count
                    Section {
                        LabeledContent("Workouts to add", value: "\(count)")
                        if count != bundle.content.sessions.count { LabeledContent("Already imported", value: "\(bundle.content.sessions.count - count)") }
                        ForEach(bundle.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section {
                        ForEach(bundle.content.sessions) { session in
                            LabeledContent(session.name, value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    Button("Add to History") { if store.perform({ _ = try $0.importHistory(bundle) }) { dismiss() } }.disabled(count == 0).accessibilityIdentifier("csv.addHistory")
                }
            }.formStyle(.grouped).navigationTitle("Import CSV").inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    func dayPreview(_ day: Routine, in data: TrainingData) -> some View {
        DisclosureGroup {
            if day.slots.isEmpty { Text("No exercises").foregroundStyle(.secondary) }
            ForEach(day.slots) { slot in
                if let variant = data.variant(slot.variantID), let exercise = data.exercise(variant.exerciseID) {
                    VStack(alignment: .leading, spacing: 4) { Text(exercise.name); Text(planSummary(variant, unit: store.data.settings.unit)).font(.caption).foregroundStyle(.secondary) }
                }
            }
        } label: { HStack { Text(day.name); Spacer(); Text(counted(day.slots.count, "exercise")).foregroundStyle(.secondary) } }
    }
    func add(_ bundle: RoutineBundle, load: Bool) {
        if store.perform({ _ = try $0.importRoutines(bundle, loadFirst: load) }) { dismiss() }
    }
}
