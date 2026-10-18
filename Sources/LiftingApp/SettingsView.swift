import SwiftUI
import LiftingCore
import UniformTypeIdentifiers
#if os(iOS)
import UserNotifications
#endif

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument()
    @State private var contentType = UTType.json
    @State private var importPreview: TrainingData?
    @State private var confirmingImport = false
    @State private var plates = false
    @State private var exportName = "Lifting-backup"
    @State private var notificationStatus = ""
    func setting<T>(_ key: WritableKeyPath<LiftingCore.Settings, T>) -> Binding<T> { Binding(get: { store.data.settings[keyPath: key] }, set: { value in store.perform { $0.settings[keyPath: key] = value } }) }
    var body: some View {
        Form {
            Section("Units") {
                Picker("Weight", selection: setting(\.unit)) { ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            Section("Workout") {
                Toggle("Auto-start rest timer", isOn: setting(\.autoRest))
                Toggle("Haptics", isOn: setting(\.haptics))
                Toggle("Keep screen awake", isOn: setting(\.keepAwake))
                #if os(iOS)
                Button("Enable background rest alerts") {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                        Task { @MainActor in notificationStatus = granted ? "Background rest alerts enabled." : "Enable alerts in iOS Settings."; if let error { store.error = error.localizedDescription } }
                    }
                }
                if !notificationStatus.isEmpty { Text(notificationStatus).font(.footnote).foregroundStyle(.secondary) }
                #endif
            }
            Section("Plates") {
                HStack { Text("Bar (\(store.data.settings.unit.rawValue))"); TextField("0", value: Binding(get: { store.data.settings.unit.display(store.data.settings.barWeight) }, set: { value in store.perform { $0.settings.barWeight = $0.settings.unit.kilograms(value) } }), format: .number).multilineTextAlignment(.trailing) }
                NavigationLink("Available plate sizes") { PlateInventoryView() }
                Button("Plate calculator") { plates = true }
            }
            Section("Appearance") {
                Picker("Theme", selection: setting(\.theme)) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
            }
            Section("Data") {
                Button("Export backup") {
                    do { document = BackupDocument(bytes: try LocalRepository.encode(store.data)); contentType = .json; exportName = "Lifting-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"; exporting = true } catch { store.error = error.localizedDescription }
                }.accessibilityIdentifier("settings.export")
                Button("Export logged sets as CSV") { document = BackupDocument(bytes: LocalRepository.csv(store.data)); contentType = .commaSeparatedText; exportName = "Lifting-sets"; exporting = true }
                Button("Import backup") { importing = true }.accessibilityIdentifier("settings.import")
                if let date = store.data.settings.lastBackupAt { Text("Last backup: \(date.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary) }
                Text("Stored on this device. No account or server.").font(.footnote).foregroundStyle(.secondary)
                if store.storageBlocked { Text("Your local files were preserved. Import a valid backup to recover.").foregroundStyle(.red) }
            }
            Section { LabeledContent("Version", value: "1.0"); Text("Backup files include all routines, variants, history, and the active workout.").font(.footnote).foregroundStyle(.secondary) }
        }.formStyle(.grouped).navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: exportName) { result in
            switch result { case .success: if contentType == .json { store.perform { $0.settings.lastBackupAt = Date() } }; case .failure(let error): store.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw TrainingError.invalid("The backup is too large.") }
                importPreview = try LocalRepository.decode(Data(contentsOf: url)); confirmingImport = true
            } catch { store.error = "Import failed. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace all data with this backup?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Replace all data", role: .destructive) { if let importPreview { store.importBackup(importPreview) }; importPreview = nil }
            Button("Cancel", role: .cancel) { importPreview = nil }
        } message: { Text("\(importPreview?.sessions.count ?? 0) workouts, \(importPreview?.routines.count ?? 0) routines, \(importPreview?.variants.count ?? 0) variants. A copy of your current data is preserved locally.") }
        .sheet(isPresented: $plates) { PlateView().environmentObject(store).sheetSize() }
    }
}

struct PlateInventoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var newSize = ""
    var unit: WeightUnit { store.data.settings.unit }
    var sizes: [Double] { unit == .lb ? store.data.settings.platesLB : store.data.settings.platesKG }
    func save(_ values: [Double]) { store.perform { if unit == .lb { $0.settings.platesLB = values } else { $0.settings.platesKG = values } } }
    var body: some View {
        Form {
            Section("\(unit.rawValue) per plate") {
                ForEach(sizes.sorted(by: >), id: \.self) { value in HStack { Text(number(value)); Spacer(); Button(role: .destructive) { save(sizes.filter { $0 != value }) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove \(number(value)) plate") } }
                HStack { TextField("Plate size", text: $newSize); Button("Add") { if let value = Double(newSize), value.isFinite, value > 0, !sizes.contains(value) { save(sizes + [value]); newSize = "" } } }
            }
        }.formStyle(.grouped).navigationTitle("Plate sizes").inlineTitle()
    }
}

struct PlateView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var initialWeight = 135.0
    @State private var target = 135.0
    var unit: WeightUnit { store.data.settings.unit }
    var result: (plates: [Double], remainder: Double) { PlateCalculator.plates(total: target, bar: unit.display(store.data.settings.barWeight), available: unit == .lb ? store.data.settings.platesLB : store.data.settings.platesKG) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Text("Target (\(unit.rawValue))"); TextField("0", value: $target, format: .number).multilineTextAlignment(.trailing) }
                    LabeledContent("Bar", value: "\(number(unit.display(store.data.settings.barWeight))) \(unit.rawValue)")
                }
                Section("Per side") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(.secondary).frame(width: 34, height: 12)
                            ForEach(Array(result.plates.enumerated()), id: \.offset) { _, plate in ZStack { RoundedRectangle(cornerRadius: 5).fill(Palette.accent.opacity(0.15)); Text(number(plate)).font(.caption.weight(.semibold)) }.frame(width: 40, height: 50 + min(90, plate * 1.5)) }
                        }.frame(minHeight: 130)
                    }
                    Text(result.plates.isEmpty ? "Bar only" : result.plates.map { number($0) }.joined(separator: " + "))
                    if target < unit.display(store.data.settings.barWeight) { Text("Target is below the bar weight.").foregroundStyle(.red) }
                    else if result.remainder > 0.01 { Text("Unloaded: \(number(result.remainder)) \(unit.rawValue)").foregroundStyle(.orange) }
                }
            }.formStyle(.grouped).navigationTitle("Plate calculator").inlineTitle().toolbar { Button("Done") { dismiss() } }
        }.onAppear { target = initialWeight }
    }
}
