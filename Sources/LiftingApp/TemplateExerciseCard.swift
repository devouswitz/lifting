import SwiftUI
import LiftingCore

/// An exercise in a saved day: the same card as the live workout, editing the prescription instead of logged sets.
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
    /// Points this day's slot at another exercise, such as the same movement on other equipment.
    var swap: ((UUID) -> Void)? = nil
    @State private var sheet: Sheet?
    @State private var reordering = false
    @State private var draggingSet: UUID?
    private var unit: WeightUnit { store.data.settings.unit }
    private var exercise: Exercise? { store.data.exercise(variant.exerciseID) }
    private var mode: ExerciseMode { exercise?.mode ?? .strength }

    private enum Sheet: Identifiable {
        case keypad(NumericEdit), reps(SetPlan), repTarget(SetPlan), load(SetPlan), details(SetPlan), technique(Technique), settings, warmups, saveWarmups
        var id: String {
            switch self {
            case .keypad(let edit): return "keypad.\(edit.id)"
            case .reps(let plan): return "reps.\(plan.id)"
            case .repTarget(let plan): return "target.\(plan.id)"
            case .load(let plan): return "load.\(plan.id)"
            case .details(let plan): return "details.\(plan.id)"
            case .technique(let technique): return "technique.\(technique.rawValue)"
            case .settings: return "settings"
            case .warmups: return "warmups"
            case .saveWarmups: return "saveWarmups"
            }
        }
    }

    var body: some View {
        let weights = variant.resolvedWeights
        ExerciseCard(name: exercise?.name ?? "Exercise", link: groupTitle, summary: planSummary(variant, unit: unit), expanded: expanded, toggle: toggle,
                     order: CardOrder(id: slotID, canMoveUp: canMoveUp, canMoveDown: canMoveDown, dragging: $dragging, move: move)) {
            EmptyView()
        } menu: { menuItems } content: {
            ExerciseInfoRow(exerciseID: variant.exerciseID, swap: swap, load: loadSummary(zip(variant.sets, weights).compactMap { $0.kind == .warmup ? nil : $1 }, mode: mode, unit: unit),
                            rest: variant.restSeconds) {
                sheet = .keypad(.rest(variant.restSeconds, context: exercise?.name) { seconds in var edited = variant; edited.restSeconds = seconds; return store.saveVariant(edited) })
            }
            TextField("Add a note", text: $variant.notes, axis: .vertical).font(.subheadline).lineLimit(1...5).padding(.bottom, 4)
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("Set").frame(width: 44)
                    Text(mode == .cardio ? "Time" : mode == .bodyweight ? "+\(unit.rawValue)" : unit.rawValue).frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                    Text("RPE").frame(width: 50)
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            if reordering { Button("Finish Reordering") { reordering = false }.font(.subheadline) }
            ForEach(Array(variant.sets.enumerated()), id: \.element.id) { index, plan in
                if plan.kind == .warmup && (index == 0 || variant.sets[index - 1].kind != .warmup) {
                    SetGroupLabel(title: "Warm-up", color: palette.warmup)
                } else if index > 0 && plan.kind != .warmup && variant.sets[index - 1].kind == .warmup {
                    SetGroupLabel(title: "Working sets", color: .secondary).padding(.top, 6)
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
            ExerciseActions(addTitle: "Add Set", quickAdds: mode != .cardio, adder: adder, customize: { sheet = .technique($0) })
        }
        .sheet(item: $sheet) { sheetContent($0).environmentObject(store) }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Plan Settings", systemImage: "slider.horizontal.3") { sheet = .settings }
        if let link { Button("Superset / Circuit", systemImage: "link", action: link) }
        Button(reordering ? "Finish Reordering" : "Reorder Sets", systemImage: "arrow.up.arrow.down") { reordering.toggle() }
        if mode != .cardio {
            Button("Add Warm-up", systemImage: "plus") { addWarmup() }
            Button("Apply Warm-up Preset", systemImage: "flame") { sheet = .warmups }
            if variant.sets.contains(where: { $0.kind == .warmup }) {
                Button("Save Warm-ups as Preset", systemImage: "square.and.arrow.down") { sheet = .saveWarmups }
                Button("Remove Warm-ups", systemImage: "minus.circle") { variant.sets.removeAll { $0.kind == .warmup } }
            }
        }
        if let remove {
            Divider()
            Button("Remove Exercise", systemImage: "trash", role: .destructive, action: remove)
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .keypad(let edit): NumberEditor(edit: edit)
        case .reps(let plan): RepValuesEditor(plan: plan, save: saveReps, adjacent: adjacentPlan)
        case .repTarget(let plan): RepTargetEditor(plan: plan, onSave: saveReps)
        case .load(let plan): LoadRuleEditor(plan: plan, unit: unit, suggestedWeight: variant.weight(for: plan)) { edited in update(plan.id) { $0 = edited } }
        case .details(let plan): TemplatePlanEditor(variant: variant, plan: plan) { edited in store.saveVariant(edited) }.sheetSize()
        case .technique(let technique):
            TechniqueEditor(technique: technique, exerciseID: variant.exerciseID) { plans, replace, _ in
                var edited = variant; edited.addTechnique(technique, plans: plans, replacing: replace); return store.saveVariant(edited)
            }.sheetSize()
        case .settings: PlanSettingsEditor(variant: variant).sheetSize()
        case .warmups: ApplyWarmupPreset(variantID: variant.id).sheetSize()
        case .saveWarmups: WarmupPresetEditor(preset: WarmupPreset(name: variant.label + " warm-up", sets: variant.sets.filter { $0.kind == .warmup })).sheetSize()
        }
    }

    private func row(_ plan: SetPlan, index: Int, weight: Double?) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        let labeled = typeSize.isAccessibilitySize
        let load = mode == .cardio ? plan.seconds.map(clockText) ?? "Time"
            : loadText(weight.flatMap { $0 == 0 && plan.load != .fixed && mode != .bodyweight ? nil : $0 }, mode: mode, unit: unit) ?? "–"
        return layout {
            VStack(spacing: 0) {
                SetTypeButton(plan: plan, change: { edited in update(plan.id) { $0 = edited } }, convert: { technique in
                    var edited = variant; edited.convertSet(plan.id, to: technique, defaults: store.data.techniqueDefaults(for: variant.exerciseID)); variant = edited
                }, details: { sheet = .details(plan) }, duplicate: { duplicate(plan) }) {
                    SetBadge(text: setBadge(variant.sets, index: index, types: store.data.customSetTypes), plan: plan)
                }.accessibilityLabel("\(palette.title(plan)), set \(index + 1), change set type")
                if plan.load == .percent {
                    Button("\(number(plan.percent))%") { open(plan.id, .percent) }
                        .font(.caption).frame(minWidth: 44, minHeight: 20)
                        .longPress("Weight settings") { sheet = .load(plan) }
                }
            }
            SetValueCell(title: mode == .cardio ? "Time" : "Weight", value: load, labeled: labeled) { open(plan.id, mode == .cardio ? .time : .weight) }
                .longPress("Weight settings") { sheet = .load(plan) }
                .accessibilityLabel("Set \(index + 1), \(mode == .cardio ? "time" : "weight"), \(load)")
            SetValueCell(title: "Reps", value: plan.repTarget.map(displayTarget) ?? "–", labeled: labeled) { sheet = .reps(plan) }
                .longPress("Edit rep target") { sheet = .repTarget(plan) }
                .accessibilityLabel("Set \(index + 1), rep target, \(plan.repTarget ?? "none")")
            SetValueCell(title: "RPE", value: plan.rpe.map { number($0) } ?? "–", labeled: labeled) { open(plan.id, .rpe) }
                .frame(maxWidth: labeled ? .infinity : 50)
                .accessibilityLabel("Set \(index + 1), RPE, \(plan.rpe.map { number($0) } ?? "none")")
        }
        .accessibilityAction(named: "Duplicate Set") { duplicate(plan) }
    }

    @discardableResult private func update(_ id: UUID, _ change: (inout SetPlan) -> Void) -> Bool {
        var edited = variant
        guard let index = edited.sets.firstIndex(where: { $0.id == id }) else { return false }
        change(&edited.sets[index])
        return store.saveVariant(edited)
    }
    private func open(_ id: UUID, _ field: SetField) {
        if let edit = numericEdit(id, field: field) { sheet = .keypad(edit) }
    }
    private func numericEdit(_ id: UUID, field: SetField) -> NumericEdit? {
        guard let index = variant.sets.firstIndex(where: { $0.id == id }) else { return nil }
        let plan = variant.sets[index]
        let value: Double?
        switch field {
        case .weight: value = variant.weight(for: plan).map(unit.display)
        case .time: value = plan.seconds
        case .rpe: value = plan.rpe
        case .percent: value = plan.percent
        default: return nil
        }
        return field.edit(value: value, context: "\(exercise?.name ?? "Exercise"), set \(setBadge(variant.sets, index: index, types: store.data.customSetTypes))", unit: unit, mode: mode,
            previous: adjacentNumericID(id, offset: -1, field: field) != nil ? { adjacentNumeric(id, offset: -1, field: field) } : nil,
            next: adjacentNumericID(id, offset: 1, field: field) != nil ? { adjacentNumeric(id, offset: 1, field: field) } : nil
        ) { value in
            if field == .weight, let value {
                var edited = variant; edited.setWeight(unit.kilograms(value), for: id)
                return store.saveVariant(edited)
            }
            return update(id) { plan in
                switch field {
                case .weight: plan.load = plan.kind == .warmup || mode == .bodyweight ? .none : .working; plan.weightOverride = nil
                case .time: plan.seconds = value
                case .rpe: plan.rpe = value
                case .percent: plan.percent = value ?? 0
                default: break
                }
            }
        }
    }
    private func adjacentPlan(_ id: UUID, offset: Int) -> SetPlan? {
        guard let index = variant.sets.firstIndex(where: { $0.id == id }), variant.sets.indices.contains(index + offset) else { return nil }
        return variant.sets[index + offset]
    }
    private func adjacentNumeric(_ id: UUID, offset: Int, field: SetField) -> NumericEdit? {
        adjacentNumericID(id, offset: offset, field: field).flatMap { numericEdit($0, field: field) }
    }
    private func adjacentNumericID(_ id: UUID, offset: Int, field: SetField) -> UUID? {
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
    private var adder: SetAdder {
        SetAdder(set: addSet, warmup: addWarmup, typed: { kind, id in
            if kind == .warmup {
                addWarmup()
                if let index = variant.sets.lastIndex(where: { $0.kind == .warmup }) { variant.sets[index].customTypeID = id }
            } else {
                addSet()
                guard let index = variant.sets.indices.last else { return }
                variant.sets[index].kind = kind; variant.sets[index].customTypeID = id
            }
        }, technique: { technique in
            variant.addTechnique(technique, plans: store.data.techniqueDefaults(for: variant.exerciseID).plans(technique), replacing: false)
        })
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
