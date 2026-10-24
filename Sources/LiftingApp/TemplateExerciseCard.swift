import SwiftUI
import LiftingCore

struct TemplateExerciseCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var variant: Variant
    let expanded: Bool
    var groupTitle: String?
    let toggle: () -> Void
    var link: (() -> Void)? = nil
    let move: (Int) -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let slotID: UUID
    @Binding var dragging: UUID?
    var remove: (() -> Void)? = nil
    @State private var numberEdit: NumericEdit?
    @State private var repEdit: SetPlan?
    @State private var repValues: SetPlan?
    @State private var loadEdit: SetPlan?
    @State private var planEdit: SetPlan?
    @State private var settings = false
    @State private var technique: TechniqueKind?
    @State private var savingWarmups = false
    @State private var warmups = false
    @State private var reordering = false
    @State private var draggingSet: UUID?
    private var unit: WeightUnit { store.data.settings.unit }
    private var exercise: Exercise? { store.data.exercise(variant.exerciseID) }

    var body: some View {
        let weights = variant.resolvedWeights
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: toggle) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise?.name ?? "Exercise").font(.headline).foregroundStyle(.primary)
                        if let groupTitle { Label(groupTitle, systemImage: "link").font(.caption).foregroundStyle(palette.technique) }
                        if !expanded { Text(planSummary(variant, unit: unit)).font(.subheadline).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .modifier(ExerciseDragHandle(id: slotID, enabled: canMoveUp || canMoveDown, dragging: $dragging))
                .modifier(ReorderActions(canMoveUp: canMoveUp, canMoveDown: canMoveDown, move: move))
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(exercise?.name ?? "exercise")")
                Menu {
                    Button("Plan Settings", systemImage: "slider.horizontal.3") { settings = true }
                    if let link { Button("Superset / Circuit", systemImage: "link", action: link) }
                    Button(reordering ? "Finish Reordering" : "Reorder Sets", systemImage: "arrow.up.arrow.down") { reordering.toggle() }
                    if exercise?.mode != .cardio {
                        Button("Add Warm-up", systemImage: "plus") { addWarmup() }
                        Button("Apply Warm-up Preset", systemImage: "flame") { warmups = true }
                        if variant.sets.contains(where: { $0.kind == .warmup }) {
                            Button("Save Warm-ups as Preset", systemImage: "square.and.arrow.down") { savingWarmups = true }
                            Button("Remove Warm-ups", systemImage: "minus.circle") { variant.sets.removeAll { $0.kind == .warmup } }
                        }
                    }
                    if let remove {
                        Divider()
                        Button("Remove Exercise", systemImage: "trash", role: .destructive, action: remove)
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 32, height: 44) }.compactMenu()
                    .accessibilityLabel("Options for \(exercise?.name ?? "exercise")")
            }
            if expanded {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    if exercise?.mode != .cardio {
                        Text(weightSummary(zip(variant.sets, weights).compactMap { $0.kind == .warmup ? nil : $1 }, unit: unit)).foregroundStyle(.secondary)
                    }
                    Button {
                        numberEdit = NumericEdit(title: "Rest (seconds)", value: Double(variant.restSeconds), step: 15, maximum: 86400, integer: true) { value in var edited = variant; edited.restSeconds = Int(value ?? 0); return store.saveVariant(edited) }
                    } label: { Text("Rest ").foregroundStyle(.secondary) + Text(clockText(Double(variant.restSeconds))).foregroundStyle(palette.rest) }
                }.font(.subheadline.weight(.medium)).buttonStyle(.plain).frame(minHeight: 36)
                TextField("Add a note", text: $variant.notes, axis: .vertical).font(.subheadline).lineLimit(1...5)
                if !typeSize.isAccessibilitySize { HStack(spacing: 8) {
                    Text("Set").frame(width: 44)
                    Text(exercise?.mode == .cardio ? "Time" : unit.rawValue).frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                    Text("RPE").frame(width: 50)
                }.font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
                if reordering { Button("Finish Reordering") { reordering = false }.font(.subheadline) }
                ForEach(Array(variant.sets.enumerated()), id: \.element.id) { index, plan in
                    if plan.kind == .warmup && (index == 0 || variant.sets[index - 1].kind != .warmup) {
                        Text("Warm-up").font(.footnote.weight(.semibold)).foregroundStyle(palette.warmup)
                    } else if index > 0 && plan.kind != .warmup && variant.sets[index - 1].kind == .warmup {
                        Text("Working sets").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if reordering {
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 44, height: 44)
                            Text(prescribedSetSummary(plan, weight: weights[index], unit: unit)).font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            .modifier(ExerciseDragHandle(id: plan.id, enabled: true, dragging: $draggingSet))
                            .modifier(ExerciseDropTarget(id: plan.id, dragging: $draggingSet, move: moveSet))
                            .modifier(ReorderActions(canMoveUp: index > 0, canMoveDown: index + 1 < variant.sets.count) { moveSet(plan.id, by: $0) })
                    } else {
                        SwipeToDelete(action: { variant.sets.removeAll { $0.id == plan.id } }) { row(plan, index: index, weight: weights[index]) }
                    }
                }
                let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                actions {
                    Button { addSet() } label: { Label("Add Set", systemImage: "plus") }.buttonStyle(FieldButtonStyle())
                    if exercise?.mode != .cardio {
                        ForEach(0..<2, id: \.self) { index in QuickAddButton(index: index, action: runQuickAdd) }
                    }
                }
            }
        }.card(padding: 16)
        .sheet(item: $numberEdit) { NumberEditor(edit: $0) }
        .sheet(item: $repValues) { plan in RepValuesEditor(plan: plan, save: saveReps, adjacent: adjacentPlan) }
        .sheet(item: $loadEdit) { plan in LoadRuleEditor(plan: plan, unit: unit, suggestedWeight: variant.weight(for: plan)) { edited in update(plan.id) { $0 = edited } } }
        .sheet(item: $repEdit) { plan in RepTargetEditor(plan: plan) { edited in update(plan.id) { $0.reps = edited.reps; $0.repCeiling = edited.repCeiling; $0.amrap = edited.amrap } } }
        .sheet(item: $planEdit) { plan in
            TemplatePlanEditor(variant: variant, plan: plan) { edited in store.saveVariant(edited) }.sheetSize()
        }
        .sheet(isPresented: $settings) { PlanSettingsEditor(variant: variant).sheetSize() }
        .sheet(isPresented: $savingWarmups) { WarmupPresetEditor(preset: WarmupPreset(name: variant.label + " warm-up", sets: variant.sets.filter { $0.kind == .warmup })).sheetSize() }
        .sheet(isPresented: $warmups) { ApplyWarmupPreset(variantID: variant.id).sheetSize() }
        .sheet(item: $technique) { kind in
            TechniqueEditor(kind: kind, workingWeight: variant.referenceWeight, rounding: variant.rounding) { plans, replace, _ in
                var edited = variant
                if replace { edited.sets.removeAll { $0.kind != .warmup } }
                if kind == .drop, let last = edited.sets.indices.last { edited.sets[last].restSeconds = 0 }
                edited.sets.append(contentsOf: plans); return store.saveVariant(edited)
            }.sheetSize()
        }
    }

    private func row(_ plan: SetPlan, index: Int, weight: Double?) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(spacing: 0) {
                SetTypeButton(plan: plan, change: { edited in update(plan.id) { $0 = edited } }, details: { planEdit = plan }, duplicate: { duplicate(plan) }) {
                    SetBadge(text: setBadge(variant.sets, index: index, types: store.data.customSetTypes), plan: plan)
                }.accessibilityLabel("\(palette.title(plan)), set \(index + 1), change set type")
                if plan.load == .percent {
                    Button("\(number(plan.percent))%") { numberEdit = numericEdit(plan.id, field: .percent) }
                        .font(.caption).frame(minWidth: 44, minHeight: 44)
                        .modifier(WeightSettingsInteraction(enabled: true) { loadEdit = plan })
                }
            }
            field(exercise?.mode == .cardio ? plan.seconds.map(clockText) ?? "Time" : weight.map { number(unit.display($0)) } ?? "–", label: "Set \(index + 1), \(exercise?.mode == .cardio ? "time" : "weight")") {
                numberEdit = numericEdit(plan.id, field: exercise?.mode == .cardio ? .time : .weight)
            }
            .modifier(WeightSettingsInteraction(enabled: true) { loadEdit = plan })
            field(plan.repTarget ?? "–", label: "Set \(index + 1), rep target") { repValues = plan }
                .modifier(RepTargetInteraction(enabled: true) { repEdit = plan })
            field(plan.rpe.map { number($0) } ?? "–", label: "Set \(index + 1), RPE") {
                numberEdit = numericEdit(plan.id, field: .rpe)
            }.frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 50)
        }
        .accessibilityAction(named: "Duplicate Set") { duplicate(plan) }
    }

    private func field(_ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 3) { if typeSize.isAccessibilitySize { Text(label).font(.caption).foregroundStyle(.secondary) }; Text(value).font(typeSize.isAccessibilitySize ? .title3.monospacedDigit() : .figure(17)) }.frame(maxWidth: .infinity, minHeight: 44).background(palette.field, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("\(label), \(value)")
    }
    @discardableResult private func update(_ id: UUID, _ change: (inout SetPlan) -> Void) -> Bool {
        var edited = variant
        guard let index = edited.sets.firstIndex(where: { $0.id == id }) else { return false }
        change(&edited.sets[index])
        return store.saveVariant(edited)
    }
    private enum Field { case weight, time, rpe, percent }
    private func numericEdit(_ id: UUID, field: Field) -> NumericEdit? {
        guard let index = variant.sets.firstIndex(where: { $0.id == id }) else { return nil }
        let plan = variant.sets[index]
        let value: Double?, title: String, step: Double, maximum: Double
        switch field {
        case .weight: value = variant.weight(for: plan).map(unit.display); title = "Weight (\(unit.rawValue))"; step = 2.5; maximum = 100000
        case .time: value = plan.seconds.map { $0 / 60 }; title = "Time (minutes)"; step = 1; maximum = 100000
        case .rpe: value = plan.rpe; title = "RPE"; step = 0.5; maximum = 10
        case .percent: value = plan.percent; title = "Percent of working set"; step = 5; maximum = 1000
        }
        return NumericEdit(title: title, context: "\(exercise?.name ?? "Exercise"), set \(setBadge(variant.sets, index: index, types: store.data.customSetTypes))", value: value, step: step, maximum: maximum, integer: false,
            previous: adjacentNumericID(id, offset: -1, field: field) != nil ? { adjacentNumeric(id, offset: -1, field: field) } : nil,
            next: adjacentNumericID(id, offset: 1, field: field) != nil ? { adjacentNumeric(id, offset: 1, field: field) } : nil
        ) { value in
            if field == .weight, let value {
                var edited = variant; edited.setWeight(unit.kilograms(value), for: id)
                return store.saveVariant(edited)
            }
            return update(id) { plan in
                switch field {
                case .weight: plan.load = plan.kind == .warmup ? .none : .working; plan.weightOverride = nil
                case .time: plan.seconds = value.map { $0 * 60 }
                case .rpe: plan.rpe = value
                case .percent: plan.percent = value ?? 0
                }
            }
        }
    }
    private func adjacentPlan(_ id: UUID, offset: Int) -> SetPlan? {
        guard let index = variant.sets.firstIndex(where: { $0.id == id }), variant.sets.indices.contains(index + offset) else { return nil }
        return variant.sets[index + offset]
    }
    private func adjacentNumeric(_ id: UUID, offset: Int, field: Field) -> NumericEdit? {
        guard let next = adjacentNumericID(id, offset: offset, field: field) else { return nil }
        return numericEdit(next, field: field)
    }
    private func adjacentNumericID(_ id: UUID, offset: Int, field: Field) -> UUID? {
        let ids = variant.sets.filter { field != .percent || $0.load == .percent }.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    private func saveReps(_ edited: SetPlan) -> Bool {
        update(edited.id) { $0.reps = edited.reps; $0.repCeiling = edited.repCeiling; $0.amrap = edited.amrap }
    }
    private func duplicate(_ plan: SetPlan) {
        guard let index = variant.sets.firstIndex(where: { $0.id == plan.id }) else { return }
        var edited = variant; var copy = plan; copy.id = UUID()
        edited.sets.insert(copy, at: index + 1); variant = edited
    }
    private func moveSet(_ id: UUID, by offset: Int) {
        guard let index = variant.sets.firstIndex(where: { $0.id == id }), variant.sets.indices.contains(index + offset) else { return }
        var edited = variant; edited.sets.swapAt(index, index + offset); variant = edited
    }
    private func moveSet(_ source: UUID, _ target: UUID, _ after: Bool) {
        var edited = variant
        guard let index = edited.sets.firstIndex(where: { $0.id == source }), source != target else { return }
        let plan = edited.sets.remove(at: index)
        guard let destination = edited.sets.firstIndex(where: { $0.id == target }) else { return }
        edited.sets.insert(plan, at: destination + (after ? 1 : 0)); variant = edited
    }
    private func runQuickAdd(_ action: QuickAdd) {
        switch action {
        case .drop: technique = .drop
        case .myo: technique = .myo
        case .warmup: addWarmup()
        case .working: addSet()
        case .failure: addTyped(.failure)
        case .myoActivation: addTyped(.myoActivation)
        case .myoMini: addTyped(.myoMini)
        case .custom(let id):
            let kind = store.data.setType(id)?.countsAs ?? .working
            if kind == .warmup {
                addWarmup()
                if let index = variant.sets.lastIndex(where: { $0.kind == .warmup }) { variant.sets[index].customTypeID = id }
            } else { addTyped(kind, customID: id) }
        }
    }
    private func addTyped(_ kind: SetKind, customID: UUID? = nil) {
        addSet()
        guard let index = variant.sets.indices.last else { return }
        variant.sets[index].kind = kind; variant.sets[index].customTypeID = customID
    }
    private func addWarmup() {
        let index = variant.sets.lastIndex(where: { $0.kind == .warmup }).map { $0 + 1 } ?? 0
        variant.sets.insert(SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil), at: index)
    }
    private func addSet() {
        var plan = variant.sets.last(where: { $0.kind == .working }) ?? exercise.flatMap { Variant.standard(for: $0, label: "").sets.first } ?? SetPlan()
        plan.id = UUID(); plan.weightOverride = nil; variant.sets.append(plan)
    }
}
