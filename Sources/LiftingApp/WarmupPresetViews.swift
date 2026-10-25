import SwiftUI
import LiftingCore

struct WarmupPresetLibrary: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: WarmupPreset?
    var body: some View {
        ThemedForm {
            ForEach(store.data.warmupPresets) { preset in
                Button { editing = preset } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preset.name).font(.headline).foregroundStyle(.primary)
                        Text(preset.sets.map { setPlanSummary($0, unit: store.data.settings.unit) }.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)
                .contextMenu {
                    Button("Duplicate") {
                        var copy = preset; copy.id = UUID(); copy.name = TrainingData.uniqueName(preset.name + " copy", among: store.data.warmupPresets.map(\.name)); editing = copy
                    }
                    Button("Delete", role: .destructive) { store.perform { $0.warmupPresets.removeAll { $0.id == preset.id } } }
                }
            }.onDelete { offsets in store.perform { $0.warmupPresets.remove(atOffsets: offsets) } }
            Button("New preset", systemImage: "plus") { editing = WarmupPreset(name: "", sets: [SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil)]) }.accessibilityIdentifier("warmups.new")
        }.formStyle(.grouped).navigationTitle("Warm-up Presets").inlineTitle()
        .sheet(item: $editing) { WarmupPresetEditor(preset: $0).environmentObject(store).sheetSize() }
    }
}

struct WarmupPresetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var preset: WarmupPreset
    var body: some View {
        DraftEditor(valid: !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && preset.name.count <= 200 && !preset.sets.isEmpty && preset.sets.allSatisfy(\.isValid), changed: store.data.warmupPresets.first { $0.id == preset.id } != preset, saveID: "warmups.save", confirmation: store.data.warmupPresets.contains { $0.id == preset.id } ? nil : "Create", save: {
            store.perform { try $0.saveWarmupPreset(preset) }
        }) {
            ThemedForm {
                StoreErrorRow()
                Section { TextField("Preset name", text: $preset.name).accessibilityIdentifier("warmups.name") }
                Section("Sets") {
                    ForEach($preset.sets) { $plan in
                        NavigationLink { PlanEditor(plan: $plan, unit: store.data.settings.unit, warmupOnly: true) } label: {
                            Text(setPlanSummary(plan, unit: store.data.settings.unit)).font(.subheadline)
                        }.accessibilityIdentifier("warmup.set.\(plan.id)")
                        .contextMenu {
                            Button("Move Up") { if let i = preset.sets.firstIndex(where: { $0.id == plan.id }), i > 0 { preset.sets.swapAt(i, i - 1) } }
                            Button("Move Down") { if let i = preset.sets.firstIndex(where: { $0.id == plan.id }), i + 1 < preset.sets.count { preset.sets.swapAt(i, i + 1) } }
                            Button("Duplicate") { var copy = plan; copy.id = UUID(); if let i = preset.sets.firstIndex(where: { $0.id == plan.id }) { preset.sets.insert(copy, at: i + 1) } }
                            Button("Delete", role: .destructive) { preset.sets.removeAll { $0.id == plan.id } }
                        }
                    }.onDelete { preset.sets.remove(atOffsets: $0) }.onMove { preset.sets.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add set", systemImage: "plus") {
                        var set = preset.sets.last ?? SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil)
                        set.id = UUID(); preset.sets.append(set)
                    }.accessibilityIdentifier("warmups.addSet")
                }
            }.formStyle(.grouped).navigationTitle(preset.name.isEmpty ? "New Preset" : preset.name).inlineTitle()
        }
    }
}

struct ApplyWarmupPreset: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var routineID: UUID?
    var exerciseID: UUID?
    var variantID: UUID?
    @State private var standard = WarmupPreset(name: "Standard: 50%, 70%, 85%", sets: [(50.0, 8), (70.0, 5), (85.0, 2)].map { SetPlan(kind: .warmup, load: .percent, percent: $0.0, reps: $0.1, repCeiling: nil) })
    private var presets: [WarmupPreset] { [standard] + store.data.warmupPresets }
    @State private var selectedPreset: UUID?
    @State private var selectedExercises: Set<UUID> = []
    @State private var replacing = true
    @State private var future = false
    @State private var creating = false
    private struct Item: Identifiable { var id: UUID; var name: String }
    private var items: [Item] {
        if let variantID, let variant = store.data.variant(variantID) {
            return [Item(id: variantID, name: store.data.exercise(variant.exerciseID)?.name ?? variant.label)]
        }
        if let routineID, let day = store.data.routine(routineID) {
            return day.slots.compactMap { slot in
                guard let v = store.data.variant(slot.variantID), let e = store.data.exercise(v.exerciseID), e.mode != .cardio else { return nil }
                return Item(id: v.id, name: e.name)
            }
        }
        return (store.data.activeSession?.exercises ?? []).filter { $0.mode != .cardio }.map { Item(id: $0.id, name: $0.name) }
    }
    var body: some View {
        NavigationStack {
            ThemedForm {
                StoreErrorRow()
                Section {
                    Picker("Preset", selection: $selectedPreset) {
                        Text("Choose preset").tag(UUID?.none)
                        ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("warmups.preset")
                    Button("New preset", systemImage: "plus") { creating = true }
                    NavigationLink("Manage presets") { WarmupPresetLibrary() }
                    if let preset = presets.first(where: { $0.id == selectedPreset }) {
                        Text(preset.sets.map { setPlanSummary($0, unit: store.data.settings.unit) }.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Exercises") {
                    ForEach(items) { item in Toggle(item.name, isOn: Binding(get: { selectedExercises.contains(item.id) }, set: { if $0 { selectedExercises.insert(item.id) } else { selectedExercises.remove(item.id) } })) }
                }
                Section {
                    Toggle(routineID == nil && variantID == nil ? "Replace pending warm-ups" : "Replace warm-ups", isOn: $replacing)
                    if routineID == nil && variantID == nil { Toggle("Save to this day", isOn: $future) }
                }
            }.formStyle(.grouped).navigationTitle("Apply Warm-up Preset").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") {
                    guard let preset = presets.first(where: { $0.id == selectedPreset }) else { return }
                    if store.perform({ data in
                        data.settings.lastWarmups = preset
                        if routineID != nil || variantID != nil { try data.applyWarmups(preset.sets, toVariants: selectedExercises, replacing: replacing) }
                        else {
                            try data.applyWarmups(preset.sets, toSessionExercises: selectedExercises, replacing: replacing, saveFuture: future)
                            if let first = data.activeSession?.exercises.first(where: { selectedExercises.contains($0.id) }) { data.setExerciseExpanded(first.id, expanded: true, focus: true) }
                        }
                    }) {
                        store.cancelRestAlert()
                        if routineID == nil, let first = store.data.activeSession?.exercises.first(where: { selectedExercises.contains($0.id) }) { store.autoFocusedExerciseID = first.id; store.autoFocusRevision += 1 }
                        dismiss()
                    }
                }.disabled(selectedPreset == nil || selectedExercises.isEmpty).accessibilityIdentifier("warmups.apply") }
            }
            .sheet(isPresented: $creating) { WarmupPresetEditor(preset: WarmupPreset(name: "", sets: [SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil)])).environmentObject(store).sheetSize() }
        }.onAppear { selectedPreset = presets.first?.id; selectedExercises = exerciseID.map { [$0] } ?? Set(items.map(\.id)) }
        .onChange(of: store.data.warmupPresets.count) { _, _ in if selectedPreset == nil { selectedPreset = store.data.warmupPresets.last?.id } }
    }
}
