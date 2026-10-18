import SwiftUI
import LiftingCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UserNotifications
#endif

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var importingCSV = false
    @State private var document = BackupDocument()
    @State private var contentType = UTType.json
    @State private var importPreview: TrainingData?
    @State private var confirmingImport = false
    @State private var plates = false
    @State private var exportName = "Lifting-backup"
    @State private var notificationStatus = ""
    @State private var choosingSyncFolder = false
    @State private var choosingMacFolder = false
    func setting<T>(_ key: WritableKeyPath<LiftingCore.Settings, T>) -> Binding<T> { Binding(get: { store.data.settings[keyPath: key] }, set: { value in store.perform { $0.settings[keyPath: key] = value } }) }
    var body: some View {
        Form {
            Section("General") {
                Picker("Weight unit", selection: setting(\.unit)) { ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Picker("Appearance", selection: setting(\.theme)) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
            }
            Section("Workout") {
                NavigationLink("Warm-up Presets") { WarmupPresetLibrary() }.accessibilityIdentifier("settings.warmups")
                Toggle("Auto-start rest timer", isOn: setting(\.autoRest))
                Toggle("Auto-collapse completed exercises", isOn: Binding(get: { store.data.settings.autoCollapseCompleted == true }, set: { value in store.perform { $0.settings.autoCollapseCompleted = value } }))
                Toggle("Haptics", isOn: setting(\.haptics))
                Toggle("Keep screen awake", isOn: setting(\.keepAwake))
                #if os(iOS)
                Button("Allow Rest Alerts in Background") {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                        Task { @MainActor in notificationStatus = granted ? "Background rest alerts enabled." : "Enable alerts in iOS Settings."; if let error { store.error = error.localizedDescription } }
                    }
                }
                if !notificationStatus.isEmpty { Text(notificationStatus).font(.footnote).foregroundStyle(.secondary) }
                #endif
            }
            Section("Plates") {
                HStack { Text("Bar weight (\(store.data.settings.unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { store.data.settings.unit.display(store.data.settings.barWeight) }, set: { value in store.perform { $0.settings.barWeight = $0.settings.unit.kilograms(value) } }), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90) }
                NavigationLink("Plate Sizes") { PlateInventoryView() }
                Button("Plate Calculator") { plates = true }
            }
            folderSyncSection
            Section {
                Button("Export Backup") {
                    do { document = BackupDocument(bytes: try LocalRepository.encode(store.data)); contentType = .json; exportName = "Lifting-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"; exporting = true } catch { store.error = error.localizedDescription }
                }.accessibilityIdentifier("settings.export")
                Button("Export Logged Sets (CSV)") { document = BackupDocument(bytes: LocalRepository.csv(store.data)); contentType = .commaSeparatedText; exportName = "Lifting-sets"; exporting = true }
                Button("Import Workout Data") { importingCSV = true }.accessibilityIdentifier("settings.importCSV")
                Button("Restore Backup") { importing = true }.accessibilityIdentifier("settings.import")
                if store.storageBlocked { Text("Your local files were preserved. Restore a valid backup to recover.").foregroundStyle(.red) }
            } header: { Text("Data") } footer: {
                if let date = store.data.settings.lastBackupAt { Text("Last exported \(date.formatted(date: .abbreviated, time: .omitted)).") }
            }
            Section { LabeledContent("Version", value: "1.0") }
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
                let bytes = try Data(contentsOf: url)
                if let library = try? LocalRepository.decode(bytes) { importPreview = library }
                else {
                    let replica = try DeviceSyncState.decode(bytes)
                    var restoring = DeviceSyncState(); importPreview = try restoring.merge([replica], into: TrainingData())
                }
                confirmingImport = true
            } catch { store.error = "Import failed. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace all data with this backup?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Replace all data", role: .destructive) { if let importPreview { store.importBackup(importPreview) }; importPreview = nil }
            Button("Cancel", role: .cancel) { importPreview = nil }
        } message: { Text("\(importPreview?.sessions.count ?? 0) workouts, \(importPreview?.programs.count ?? 0) programs, \(importPreview?.routines.count ?? 0) days, \(importPreview?.variants.count ?? 0) variants. A copy of your current data is preserved locally.") }
        .modifier(CSVImportModifier(isPresented: $importingCSV))
        .background {
            Color.clear.frame(width: 1, height: 1).fileImporter(isPresented: $choosingSyncFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                do { if let url = try result.get().first { store.chooseSyncFolder(url) } } catch { store.syncStatus = error.localizedDescription }
            }
        }
        .sheet(isPresented: $plates) { PlateView().environmentObject(store).sheetSize() }
    }
    private var folderSyncSection: some View {
            Section {
                Button(store.syncConfiguration.bookmark == nil ? "Choose iCloud Drive or other folder" : "Folder: \(store.syncConfiguration.name)", action: chooseFolder).disabled(store.syncing || choosingMacFolder).accessibilityIdentifier("settings.syncFolder")
                Toggle("Automatic backup", isOn: Binding(get: { store.syncConfiguration.automaticBackup }, set: { value in store.configureSync { $0.automaticBackup = value } })).disabled(store.syncConfiguration.bookmark == nil).accessibilityIdentifier("settings.autoBackup")
                Toggle("Device sync", isOn: Binding(get: { store.syncConfiguration.deviceSync }, set: { value in store.configureSync { $0.deviceSync = value } })).disabled(store.syncConfiguration.bookmark == nil).accessibilityIdentifier("settings.deviceSync")
                if store.syncConfiguration.automaticBackup || store.syncConfiguration.deviceSync {
                    Button(store.syncing ? "Syncing…" : "Sync now") { Task { await store.syncNow() } }.disabled(store.syncing).accessibilityIdentifier("settings.syncNow")
                    Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                    if let date = store.lastFolderSync { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                if store.syncConfiguration.bookmark != nil {
                    Button("Disconnect folder") { store.configureSync { $0.bookmark = nil; $0.name = ""; $0.automaticBackup = false; $0.deviceSync = false } }
                }
            } header: { Text("Backup and sync") } footer: { Text("Choose the same iCloud Drive folder on each device. Sync runs while the app is open. History merges after the active workout ends.") }
    }
    private func chooseFolder() {
        #if os(macOS)
        guard !choosingMacFolder else { return }; choosingMacFolder = true
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Choose"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            choosingMacFolder = false
            if response == .OK, let url = panel.url { store.chooseSyncFolder(url) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
        #else
        choosingSyncFolder = true
        #endif
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
                HStack { TextField("Plate size", text: $newSize).labelsHidden()
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    Button("Add") { if let value = Double(newSize.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0, !sizes.contains(value) { save(sizes + [value]); newSize = "" } }.disabled(Double(newSize.replacingOccurrences(of: ",", with: ".")) == nil) }
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
                    HStack { Text("Target (\(unit.rawValue))"); Spacer(); TextField("0", value: $target, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 110) }
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
