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
    @Environment(\.palette) var palette
    @Environment(\.scenePhase) private var phase
    @State private var exporting = false
    @State private var importing = false
    @State private var importingCSV = false
    @State private var document = BackupDocument()
    @State private var contentType = UTType.json
    @State private var importPreview: TrainingData?
    @State private var confirmingImport = false
    @State private var exportName = "Setform-backup"
    @State private var notificationStatus = ""
    @State private var choosingSyncFolder = false
    @State private var choosingMacFolder = false
    func setting<T>(_ key: WritableKeyPath<LiftingCore.Settings, T>) -> Binding<T> { Binding(get: { store.data.settings[keyPath: key] }, set: { value in store.perform { $0.settings[keyPath: key] = value } }) }
    var body: some View {
        ThemedForm {
            Section("General") {
                LabeledContent {
                    Picker("Weight unit", selection: setting(\.unit)) { ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 110)
                } label: { TileLabel(title: "Weight Unit", symbol: "scalemass.fill", color: .gray) }
                Picker(selection: setting(\.theme)) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") } label: { TileLabel(title: "Appearance", symbol: "circle.lefthalf.filled", color: .indigo) }
                NavigationLink { ColorSettingsView() } label: { HStack { TileLabel(title: "Colors", symbol: "paintpalette.fill", color: palette.technique); Spacer(); ColorSwatches() } }.accessibilityIdentifier("settings.colors")
            }
            Section("Workout") {
                NavigationLink { WarmupPresetLibrary() } label: { TileLabel(title: "Warm-up Presets", symbol: "flame.fill", color: palette.warmup) }.accessibilityIdentifier("settings.warmups")
                NavigationLink { SetTypesView() } label: { TileLabel(title: "Set Types", symbol: "square.stack.3d.up.fill", color: palette.technique) }.accessibilityIdentifier("settings.settypes")
                Toggle(isOn: setting(\.autoRest)) { TileLabel(title: "Start Rest Timer Automatically", symbol: "timer", color: palette.rest) }
                RestStepPicker(tiled: true)
                #if os(iOS)
                Button {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        if await center.notificationSettings().authorizationStatus == .denied {
                            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
                        } else {
                            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                            catch { store.error = error.localizedDescription }
                            await updateNotificationStatus()
                            store.refreshWorkoutReminders()
                        }
                    }
                } label: { HStack { TileLabel(title: "Workout & Rest Alerts", symbol: "bell.badge.fill", color: palette.failure); Spacer(); Text(notificationStatus.isEmpty ? "Allow" : notificationStatus).foregroundStyle(notificationStatus.isEmpty ? palette.action : .secondary) } }
                .task { await updateNotificationStatus() }
                .onChange(of: phase) { _, value in if value == .active { Task { await updateNotificationStatus() } } }
                #endif
                Toggle(isOn: Binding(get: { store.data.settings.remindsAboutUnfinishedWorkouts }, set: { value in store.perform { $0.settings.workoutReminders = value }; if value { store.requestWorkoutAlerts() } })) { TileLabel(title: "Unfinished Workout Reminders", symbol: "bell.fill", color: palette.rest) }
                Toggle(isOn: Binding(get: { store.data.settings.collapsesCompletedExercises }, set: { value in store.perform { $0.settings.autoCollapseCompleted = value } })) { TileLabel(title: "Collapse Finished Exercises", symbol: "rectangle.compress.vertical", color: palette.completed) }
                Toggle(isOn: setting(\.haptics)) { TileLabel(title: "Haptics", symbol: "hand.tap.fill", color: .pink) }
                Toggle(isOn: setting(\.keepAwake)) { TileLabel(title: "Keep Screen On During Workouts", symbol: "sun.max.fill", color: .orange) }
            }
            Section("Plates") {
                NumberRow("Bar Weight (\(store.data.settings.unit.rawValue))", value: Binding(get: { store.data.settings.barWeight }, set: { value in store.perform { $0.settings.barWeight = value } }), factor: store.data.settings.unit.kilograms(1))
                NavigationLink { PlateInventoryView() } label: { TileLabel(title: "Plate Sizes", symbol: "circle.circle.fill", color: .gray) }
                NavigationLink { PlateCalculatorView() } label: { TileLabel(title: "Plate Calculator", symbol: "plus.forwardslash.minus", color: palette.action) }
            }
            #if canImport(HealthKit) && os(iOS)
            if store.health != nil { healthSection }
            #endif
            folderSyncSection
            Section {
                Button {
                    do { document = BackupDocument(bytes: try LocalRepository.encode(store.data)); contentType = .json; exportName = "Setform-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"; exporting = true } catch { store.error = error.localizedDescription }
                } label: { TileLabel(title: "Export Backup", symbol: "square.and.arrow.up.fill", color: palette.completed) }.accessibilityIdentifier("settings.export")
                Button { document = BackupDocument(bytes: LocalRepository.csv(store.data)); contentType = .commaSeparatedText; exportName = "Setform-sets"; exporting = true } label: { TileLabel(title: "Export Logged Sets as CSV", symbol: "tablecells.fill", color: palette.completed) }
                Button { importingCSV = true } label: { TileLabel(title: "Import Workout Data", symbol: "square.and.arrow.down.fill", color: palette.action) }.accessibilityIdentifier("settings.importCSV")
                Button { importing = true } label: { TileLabel(title: "Restore Backup", symbol: "clock.arrow.circlepath", color: palette.warmup) }.accessibilityIdentifier("settings.import")
                if store.storageBlocked { Text("Your local files were preserved. Restore a valid backup to recover.").foregroundStyle(.red) }
            } header: { Text("Data") } footer: {
                if let date = store.data.settings.lastBackupAt { Text("Last exported \(date.formatted(date: .abbreviated, time: .omitted)).") }
            }
            Section {
                Link(destination: URL(string: "https://ko-fi.com/devouswitz")!) {
                    HStack { TileLabel(title: "Support Setform on Ko-fi", symbol: "heart.fill", color: .pink); Spacer(); Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                }.accessibilityIdentifier("settings.kofi")
                LabeledContent("Version", value: "1.0")
            }
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
    }

    #if os(iOS)
    private func updateNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: notificationStatus = "On"
        case .denied: notificationStatus = "iOS Settings"
        default: notificationStatus = ""
        }
    }
    #endif
    #if canImport(HealthKit) && os(iOS)
    private var healthSection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.healthSettings.read }, set: { on in Task { await store.setHealthRead(on) } })) {
                TileLabel(title: "Add Calories from Apple Health", symbol: "heart.fill", color: .pink)
            }.accessibilityIdentifier("settings.healthRead")
            Toggle(isOn: Binding(get: { store.healthSettings.write }, set: { on in Task { await store.setHealthWrite(on) } })) {
                TileLabel(title: "Save Workouts to Apple Health", symbol: "square.and.arrow.down.fill", color: .pink)
            }.disabled(!store.healthSettings.read).accessibilityIdentifier("settings.healthWrite")
            if let status = store.healthStatus { Label(status, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Apple Health") } footer: {
            Text("Calories and heart rate come from the Apple Watch or other workout recorded at the same time. Setform never changes those workouts. With saving on, Setform adds a workout only when nothing else recorded that time, and removes it if a watch workout appears later.")
        }
    }
    #endif

    private var folderSyncSection: some View {
            Section {
                Button(action: chooseFolder) { HStack { TileLabel(title: "Folder", symbol: "folder.fill", color: palette.action); Spacer(); Text(store.syncConfiguration.bookmark == nil ? "Choose" : store.syncConfiguration.name).foregroundStyle(store.syncConfiguration.bookmark == nil ? palette.action : .secondary).lineLimit(1) } }
                    .disabled(store.syncing || choosingMacFolder).accessibilityIdentifier("settings.syncFolder")
                Toggle(isOn: Binding(get: { store.syncConfiguration.automaticBackup }, set: { value in store.configureSync { $0.automaticBackup = value } })) { TileLabel(title: "Automatic Backup", symbol: "externaldrive.fill", color: .gray) }.disabled(store.syncConfiguration.bookmark == nil).accessibilityIdentifier("settings.autoBackup")
                Toggle(isOn: Binding(get: { store.syncConfiguration.deviceSync }, set: { value in store.configureSync { $0.deviceSync = value } })) { TileLabel(title: "Sync Between Devices", symbol: "arrow.triangle.2.circlepath", color: .gray) }.disabled(store.syncConfiguration.bookmark == nil).accessibilityIdentifier("settings.deviceSync")
                if store.syncConfiguration.automaticBackup || store.syncConfiguration.deviceSync {
                    Button(store.syncing ? "Syncing…" : "Sync Now") { Task { await store.syncNow() } }.disabled(store.syncing).accessibilityIdentifier("settings.syncNow")
                    Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                    if let date = store.lastFolderSync { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                if store.syncConfiguration.bookmark != nil {
                    Button("Disconnect Folder", role: .destructive) { store.configureSync { $0.bookmark = nil; $0.name = ""; $0.automaticBackup = false; $0.deviceSync = false } }
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
        ThemedForm {
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

/// Plate calculator as a sheet, opened from a workout.
struct PlateView: View {
    @Environment(\.dismiss) var dismiss
    var initialWeight = 135.0
    var body: some View {
        NavigationStack { PlateCalculatorView(initialWeight: initialWeight).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
    }
}

/// Plates per side for a target weight.
struct PlateCalculatorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    var initialWeight = 135.0
    @State private var target = 135.0
    var unit: WeightUnit { store.data.settings.unit }
    var result: (plates: [Double], remainder: Double) { PlateCalculator.plates(total: target, bar: unit.display(store.data.settings.barWeight), available: unit == .lb ? store.data.settings.platesLB : store.data.settings.platesKG) }
    var body: some View {
        ThemedForm {
            Section {
                NumberRow("Target (\(unit.rawValue))", value: $target)
                LabeledContent("Bar", value: "\(number(unit.display(store.data.settings.barWeight))) \(unit.rawValue)")
            }
            Section("Per side") {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(.secondary).frame(width: 34, height: 12)
                        ForEach(Array(result.plates.enumerated()), id: \.offset) { _, plate in ZStack { RoundedRectangle(cornerRadius: 5).fill(palette.action.opacity(0.15)); Text(number(plate)).font(.caption.weight(.semibold)) }.frame(width: 40, height: 50 + min(90, plate * 1.5)) }
                    }.frame(minHeight: 130)
                }
                Text(result.plates.isEmpty ? "Bar only" : result.plates.map { number($0) }.joined(separator: " + "))
                if target < unit.display(store.data.settings.barWeight) { Text("Target is below the bar weight.").foregroundStyle(palette.failure) }
                else if result.remainder > 0.01 { Text("Unloaded: \(number(result.remainder)) \(unit.rawValue)").foregroundStyle(palette.warmup) }
            }
        }.formStyle(.grouped).navigationTitle("Plate Calculator").inlineTitle()
        .onAppear { target = initialWeight }
    }
}
