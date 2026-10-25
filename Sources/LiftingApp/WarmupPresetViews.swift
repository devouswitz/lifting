import SwiftUI
import LiftingCore

/// Settings > Warm-up Presets. Each preset opens in the Warm-ups sheet.
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
            Button("New preset", systemImage: "plus") { editing = WarmupPreset(name: "", sets: [WarmupsSheet.newRow()]) }.accessibilityIdentifier("warmups.new")
        }.formStyle(.grouped).navigationTitle("Warm-up Presets").inlineTitle()
        .sheet(item: $editing) { WarmupsSheet(preset: $0).environmentObject(store).sheetSize() }
    }
}

/// Warm-ups in one place: preset chips, the rows as the card shows them (editable), the exercises they go to,
/// and saving the rows as a preset. Opened from an exercise, a day, the workout, or a preset in Settings.
struct WarmupsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    private enum Scope { case day(UUID), variant(UUID), workout, sessionExercise(UUID), preset }
    private enum Source: Hashable { case current, preset(UUID), new }
    private struct Item: Identifiable { var id: UUID; var name: String; var warmups: [SetPlan] }
    private enum RowSheet: Identifiable {
        case keypad(NumericEdit), reps(UUID), details(UUID)
        var id: String {
            switch self { case .keypad(let edit): return "keypad.\(edit.id)"; case .reps(let id): return "reps.\(id)"; case .details(let id): return "details.\(id)" }
        }
    }
    private let scope: Scope
    @State private var source = Source.preset(WarmupPreset.standard.id)
    @State private var rows: [SetPlan] = []
    @State private var loaded = false
    @State private var selected: Set<UUID> = []
    @State private var replacing = true
    @State private var saveToDay = false
    @State private var presetID: UUID?
    @State private var presetName = ""
    @State private var naming = false
    @State private var newName = ""
    @State private var sheet: RowSheet?

    init(routineID: UUID) { scope = .day(routineID) }
    init(variantID: UUID) { scope = .variant(variantID) }
    /// The live workout, with one exercise selected or all of them.
    init(exerciseID: UUID? = nil) { scope = exerciseID.map(Scope.sessionExercise) ?? .workout }
    init(preset: WarmupPreset) {
        scope = .preset
        _rows = State(initialValue: preset.sets); _loaded = State(initialValue: true)
        _presetID = State(initialValue: preset.id); _presetName = State(initialValue: preset.name)
    }
    static func newRow() -> SetPlan { SetPlan(kind: .warmup, load: .percent, percent: 50, reps: 5, repCeiling: nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StoreErrorRow()
                    if case .preset = scope {
                        TextField("Preset name", text: $presetName).padding(16).card(padding: 0).accessibilityIdentifier("warmups.name")
                    } else { chips }
                    table
                    if !items.isEmpty { targets }
                }.padding(16)
            }
            .background(palette.background)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(isPresetScope ? (presetName.isEmpty ? "New Preset" : presetName) : "Warm-ups").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                if let focus, let subtitle = subtitle(focus) {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) { Text("Warm-ups").font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .sheet(item: $sheet) { rowSheet($0).environmentObject(store) }
            .alert("Save as Preset", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Save") { saveNewPreset() }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if focusWarmups?.isEmpty == false { chip("Current", .current) }
                ForEach(presets) { chip($0.name, .preset($0.id)) }
                Button { pick(.new) } label: { Label("New", systemImage: "plus") }.buttonStyle(ChipStyle(selected: source == .new, role: .action))
            }.padding(.horizontal, 2)
        }
    }
    private func chip(_ title: String, _ value: Source) -> some View {
        Button(title) { pick(value) }.buttonStyle(ChipStyle(selected: source == value, role: .warmup))
    }

    private var table: some View {
        let unit = store.data.settings.unit
        let allPercent = rows.allSatisfy { $0.load == .percent }
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Set").frame(width: 44)
                Text(allPercent ? "%" : "Load").frame(maxWidth: .infinity)
                if basis != nil { Text(unit.rawValue).frame(maxWidth: .infinity) }
                Text("Reps").frame(maxWidth: .infinity)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, plan in
                SwipeToDelete(action: { rows.removeAll { $0.id == plan.id } }) { row(plan, index: index, unit: unit) }
            }
            Button { var next = rows.last ?? Self.newRow(); next.id = UUID(); rows.append(next) } label: { Label("Add Warm-up", systemImage: "plus") }
                .buttonStyle(FieldButtonStyle()).padding(.top, 2).accessibilityIdentifier("warmups.addSet")
        }.card(padding: 16)
    }

    private func row(_ plan: SetPlan, index: Int, unit: WeightUnit) -> some View {
        HStack(spacing: 8) {
            Button { sheet = .details(plan.id) } label: { SetBadge(text: "W\(index + 1)", plan: plan).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel("Warm-up \(index + 1) details")
            switch plan.load {
            case .percent:
                SetValueCell(title: "Percent", value: number(plan.percent)) { sheet = .keypad(percentEdit(plan)) }
            case .fixed:
                SetValueCell(title: "Weight", value: number(unit.display(plan.fixedWeight))) { sheet = .keypad(weightEdit(plan, unit: unit)) }
            case .working, .none:
                SetValueCell(title: "Load", value: plan.load == .working ? "Work" : "–", dimmed: true) { sheet = .details(plan.id) }
            }
            if let basis {
                Text(plan.load == .none ? "–" : plan.resolvedWeight(working: basis.referenceWeight, increment: basis.rounding).map { number(unit.display($0)) } ?? "–")
                    .font(.figure(17, weight: .regular)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            SetValueCell(title: "Reps", value: plan.repTarget.map(displayTarget) ?? "–") { sheet = .reps(plan.id) }
        }
    }

    private var targets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apply to").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    let on = selected.contains(item.id)
                    Button { if on { selected.remove(item.id) } else { selected.insert(item.id) } } label: {
                        HStack(spacing: 6) {
                            if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                            Text(item.name)
                        }
                    }.buttonStyle(ChipStyle(selected: on, role: .action)).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Picker("Existing warm-ups", selection: $replacing) {
                Text("Replace warm-ups").tag(true)
                Text("Add to existing").tag(false)
            }.pickerStyle(.segmented).padding(.top, 4)
            if isLive { Toggle("Also save to the day", isOn: $saveToDay).padding(.horizontal, 16).padding(.vertical, 10).card(padding: 0) }
            if removable {
                Button("Remove Warm-ups", role: .destructive, action: removeWarmups).frame(maxWidth: .infinity).padding(.top, 4)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button(action: isPresetScope ? savePreset : apply) {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }.buttonStyle(AccentButtonStyle()).disabled(!canFinish).accessibilityIdentifier("warmups.apply")
            if !isPresetScope, let title = secondaryTitle {
                Button(title) { if case .preset(let id) = source, editablePreset(id) != nil { saveChanges(id) } else { newName = ""; naming = true } }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 40)
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4).background(palette.background)
    }

    @ViewBuilder private func rowSheet(_ sheet: RowSheet) -> some View {
        switch sheet {
        case .keypad(let edit): NumberEditor(edit: edit)
        case .reps(let id):
            if let plan = rows.first(where: { $0.id == id }) { RepValuesEditor(plan: plan) { edited in replace(edited); return true } }
        case .details(let id):
            if let index = rows.firstIndex(where: { $0.id == id }) {
                NavigationStack {
                    WarmupSetEditor(plan: Binding(get: { rows.first { $0.id == id } ?? rows[min(index, rows.count - 1)] }, set: replace),
                                    badge: "W\(index + 1)", name: focus?.name, weight: basis.flatMap { b in rows[index].resolvedWeight(working: b.referenceWeight, increment: b.rounding) },
                                    remove: rows.count > 1 ? { rows.removeAll { $0.id == id } } : nil)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
                }.sheetSize()
            }
        }
    }

    // MARK: Data

    private var isPresetScope: Bool { if case .preset = scope { return true }; return false }
    private var isLive: Bool { switch scope { case .workout, .sessionExercise: return true; default: return false } }
    private var presets: [WarmupPreset] { [WarmupPreset.standard] + store.data.warmupPresets }
    private func editablePreset(_ id: UUID) -> WarmupPreset? { store.data.warmupPresets.first { $0.id == id } }

    /// The exercises warm-ups can go to.
    private var items: [Item] {
        switch scope {
        case .preset: return []
        case .day(let id): return dayItems(store.data.routine(id))
        case .variant(let id): return dayItems(store.data.routines.first { $0.slots.contains { $0.variantID == id } }, fallback: id)
        case .workout, .sessionExercise:
            return (store.data.activeSession?.exercises ?? []).filter { $0.mode != .cardio }
                .map { Item(id: $0.id, name: $0.name, warmups: $0.sets.map(\.plan).filter { $0.kind == .warmup }) }
        }
    }
    private func dayItems(_ day: Routine?, fallback: UUID? = nil) -> [Item] {
        let ids = day?.slots.map(\.variantID) ?? fallback.map { [$0] } ?? []
        return ids.compactMap { id in
            guard let v = store.data.variant(id), let e = store.data.exercise(v.exerciseID), e.mode != .cardio else { return nil }
            return Item(id: v.id, name: e.name, warmups: v.sets.filter { $0.kind == .warmup })
        }
    }
    /// The exercise the sheet was opened from, if one.
    private var focus: Item? {
        switch scope {
        case .variant(let id), .sessionExercise(let id): return items.first { $0.id == id }
        default: return nil
        }
    }
    private var focusWarmups: [SetPlan]? { focus?.warmups }
    /// The weights the rows resolve against, for the opened exercise.
    private var basis: Variant? {
        switch scope {
        case .variant(let id): return store.data.variant(id)
        case .sessionExercise(let id):
            guard let item = store.data.activeSession?.exercises.first(where: { $0.id == id }), var variant = store.data.variant(item.variantID) else { return nil }
            variant.workingWeight = item.workingLoad(fallback: variant.workingWeight); variant.rounding = item.roundingIncrement ?? variant.rounding
            return variant
        default: return nil
        }
    }
    private func subtitle(_ focus: Item) -> String? {
        let unit = store.data.settings.unit
        guard let basis, let load = loadText(basis.referenceWeight, mode: .strength, unit: unit) else { return focus.name }
        return "\(focus.name) · \(load) \(unit.rawValue) working"
    }

    private func sourceRows(_ source: Source) -> [SetPlan] {
        switch source {
        case .current: return focusWarmups ?? []
        case .preset(let id): return presets.first { $0.id == id }?.sets ?? []
        case .new: return [Self.newRow()]
        }
    }
    private var sourceName: String? { if case .preset(let id) = source { return presets.first { $0.id == id }?.name }; return nil }
    /// Edited compares targets and loads, not set identities.
    private var edited: Bool { Self.stripped(rows) != Self.stripped(sourceRows(source)) }
    private static func stripped(_ plans: [SetPlan]) -> [SetPlan] { plans.map { var plan = $0; plan.id = WarmupPreset.standard.id; plan.kind = .warmup; return plan } }

    private var primaryTitle: String {
        if isPresetScope { return store.data.warmupPresets.contains { $0.id == presetID } ? "Save Preset" : "Create Preset" }
        if selected.count == 1, let item = items.first(where: { selected.contains($0.id) }) { return "Apply to \(item.name)" }
        return "Apply to \(selected.count) Exercises"
    }
    private var secondaryTitle: String? {
        if case .preset(let id) = source, let preset = editablePreset(id) { return edited ? "Save Changes to \(preset.name)" : nil }
        if case .preset = source, !edited { return nil }
        return "Save as New Preset"
    }
    private var canFinish: Bool {
        guard !rows.isEmpty, rows.allSatisfy(\.isValid) else { return false }
        return isPresetScope ? !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !selected.isEmpty
    }
    private var removable: Bool { items.contains { selected.contains($0.id) && !$0.warmups.isEmpty } }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch scope {
        case .variant(let id), .sessionExercise(let id): selected = [id]
        default: selected = Set(items.map(\.id))
        }
        let last = store.data.settings.lastWarmups
        pick(last.flatMap { last in presets.contains { $0.id == last.id } ? .preset(last.id) : nil } ?? .preset(WarmupPreset.standard.id))
    }
    private func pick(_ value: Source) { source = value; rows = sourceRows(value) }
    private func replace(_ plan: SetPlan) { if let index = rows.firstIndex(where: { $0.id == plan.id }) { rows[index] = plan } }

    private func apply() {
        let plans = rows
        // The menu's one-tap repeat offers exactly what was applied.
        let last = !edited && sourceName != nil ? WarmupPreset(id: presetIDForSource ?? UUID(), name: sourceName!, sets: plans) : WarmupPreset(name: "Last Warm-ups", sets: plans)
        let ids = selected, replacing = replacing, saveToDay = saveToDay
        let live = isLive
        guard store.perform({ data in
            data.settings.lastWarmups = last
            if live { try data.applyWarmups(plans, toSessionExercises: ids, replacing: replacing, saveFuture: saveToDay) }
            else { try data.applyWarmups(plans, toVariants: ids, replacing: replacing) }
        }) else { return }
        if live {
            store.cancelRestAlert()
            if let first = store.data.activeSession?.exercises.first(where: { ids.contains($0.id) }) {
                store.perform { $0.setExerciseExpanded(first.id, expanded: true, focus: true) }
                store.autoFocusedExerciseID = first.id; store.autoFocusRevision += 1
            }
        }
        dismiss()
    }
    private var presetIDForSource: UUID? { if case .preset(let id) = source { return id }; return nil }
    private func removeWarmups() {
        let ids = selected, live = isLive
        if store.perform({ data in if live { data.removePendingWarmups(fromSessionExercises: ids) } else { data.removeWarmups(fromVariants: ids) } }) { dismiss() }
    }
    private func saveChanges(_ id: UUID) {
        guard let preset = editablePreset(id) else { return }
        if store.perform({ try $0.saveWarmupPreset(WarmupPreset(id: id, name: preset.name, sets: rows)) }) { rows = sourceRows(source) }
    }
    private func saveNewPreset() {
        let preset = WarmupPreset(name: newName, sets: rows)
        if store.perform({ try $0.saveWarmupPreset(preset) }) { pick(.preset(preset.id)) }
    }
    private func savePreset() {
        if store.perform({ try $0.saveWarmupPreset(WarmupPreset(id: presetID ?? UUID(), name: presetName, sets: rows)) }) { dismiss() }
    }

    private func percentEdit(_ plan: SetPlan) -> NumericEdit {
        NumericEdit(title: "Percent of Working Set", context: focus?.name, value: plan.percent, step: 5, maximum: 1000) { value in
            var edited = plan; edited.percent = value ?? 0; replace(edited); return true
        }
    }
    private func weightEdit(_ plan: SetPlan, unit: WeightUnit) -> NumericEdit {
        NumericEdit(title: "Weight", context: focus?.name, value: unit.display(plan.fixedWeight), step: unit == .kg ? 2.5 : 5, maximum: 10000) { value in
            var edited = plan; edited.fixedWeight = unit.kilograms(value ?? 0); replace(edited); return true
        }
    }
}

/// The checkmark that closes a sheet whose edits are already applied.
struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly) }
}

/// Repeats the most recently applied warm-ups in one tap, from an exercise's menu.
struct RepeatWarmupsButton: View {
    let last: WarmupPreset
    let apply: () -> Void
    var body: some View {
        Button(action: apply) {
            Label("Apply \(last.name)", systemImage: "flame.fill")
            if last.sets.allSatisfy({ $0.load == .percent }) { Text(last.sets.map { "\(number($0.percent))%" }.joined(separator: ", ")) }
        }
    }
}
