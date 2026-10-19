import SwiftUI
import LiftingCore

struct ExternalImportSetup: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let bytes: Data
    @State private var headers: [String] = []
    @State private var options = ExternalCSVOptions()
    @State private var preview: HistoryBundle?
    @State private var error: String?
    var body: some View {
        Group {
            if let preview { CSVImportPreview(routines: nil, history: preview, onBack: { self.preview = nil }) }
            else {
                NavigationStack {
                    ThemedForm {
                        Section {
                            LabeledContent("Detected format", value: options.source)
                            Picker("Unspecified weight units", selection: $options.weightUnit) { ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) } }
                            Picker("Unspecified distance units", selection: $options.distanceUnit) { Text("Meters").tag("m"); Text("Kilometers").tag("km"); Text("Miles").tag("mi") }
                            Picker("Set duration units", selection: $options.timeUnit) { Text("Seconds").tag("s"); Text("Minutes").tag("min") }
                            Picker("Date format", selection: $options.dateFormat) {
                                Text("Automatic / ISO").tag(""); Text("Day / month / year").tag("dd/MM/yyyy"); Text("Month / day / year").tag("MM/dd/yyyy")
                                Text("Day / month / year + time").tag("dd/MM/yyyy HH:mm:ss"); Text("Month / day / year + time").tag("MM/dd/yyyy HH:mm:ss")
                            }
                            TextField("Program name (optional)", text: $options.programName)
                        }
                        Section("Columns") {
                            ForEach([ImportField.date, .workout, .exercise, .weight, .reps]) { field in column(field) }
                            DisclosureGroup("More columns") {
                                ForEach(ImportField.allCases.filter { ![.date, .workout, .exercise, .weight, .reps].contains($0) }) { field in column(field) }
                            }
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                    }.formStyle(.grouped).navigationTitle("Import \(options.source)").inlineTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) { Button("Preview") {
                            do { preview = try ExternalHistoryCSV.decode(bytes, options: options); error = nil } catch { self.error = error.localizedDescription }
                        }.disabled(options.columns[.date] == nil || options.columns[.exercise] == nil).accessibilityIdentifier("csv.previewExternal") }
                    }
                }
            }
        }.onAppear {
            guard headers.isEmpty else { return }
            do {
                headers = try CSVCodec.parse(bytes)[0]; options = ExternalHistoryCSV.detect(headers)
                if let column = options.columns[.weight], !ExternalHistoryCSV.normalized(column).contains("kg"), !ExternalHistoryCSV.normalized(column).contains("lb") { options.weightUnit = store.data.settings.unit }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func column(_ field: ImportField) -> some View {
        Picker(field.title, selection: Binding(get: { options.columns[field] ?? "" }, set: { options.columns[field] = $0.isEmpty ? nil : $0 })) {
            Text("Not included").tag("")
            ForEach(headers, id: \.self) { Text($0).tag($0) }
        }
    }
}
