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
    let link: () -> Void
    let move: (Int) -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let slotID: UUID
    @Binding var dragging: UUID?
    let remove: () -> Void
    @State private var numberEdit: NumericEdit?
    @State private var repEdit: SetPlan?
    @State private var planEdit: SetPlan?
    @State private var settings = false
    @State private var technique: TechniqueKind?
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
                .modifier(ExerciseDragHandle(id: slotID, enabled: true, dragging: $dragging))
                .modifier(ReorderActions(canMoveUp: canMoveUp, canMoveDown: canMoveDown, move: move))
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(exercise?.name ?? "exercise")")
                Menu {
                    Button("Exercise Settings", systemImage: "slider.horizontal.3") { settings = true }
                    Button("Superset / Circuit", systemImage: "link", action: link)
                    if exercise?.mode != .cardio {
                    Menu("Warm-ups", systemImage: "flame") {
                        Button("Add Warm-up") { addWarmup() }
                        ForEach(store.data.warmupPresets) { preset in
                            Button(preset.name) { variant.sets = TrainingData.applyingWarmups(preset.sets, to: variant.sets, replacing: true) }
                        }
                    }
                    }
                    Divider()
                    Button("Remove Exercise", systemImage: "trash", role: .destructive, action: remove)
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
                        numberEdit = NumericEdit(title: "Rest (seconds)", value: Double(variant.restSeconds), step: 15, maximum: 86400, integer: true) { variant.restSeconds = Int($0 ?? 0) }
                    } label: { Text("Rest ").foregroundStyle(.secondary) + Text(clockText(Double(variant.restSeconds))).foregroundStyle(palette.rest) }
                }.font(.subheadline.weight(.medium)).buttonStyle(.plain).frame(minHeight: 36)
                TextField("Add a note", text: $variant.notes, axis: .vertical).font(.subheadline).lineLimit(1...5)
                if !typeSize.isAccessibilitySize { HStack(spacing: 8) {
                    Text("Set").frame(width: 36)
                    Text(exercise?.mode == .cardio ? "Time" : unit.rawValue).frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                    Text("RPE").frame(width: 50)
                }.font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
                ForEach(Array(variant.sets.enumerated()), id: \.element.id) { index, plan in
                    if plan.kind == .warmup && (index == 0 || variant.sets[index - 1].kind != .warmup) {
                        Text("Warm-up").font(.footnote.weight(.semibold)).foregroundStyle(palette.warmup)
                    } else if index > 0 && plan.kind != .warmup && variant.sets[index - 1].kind == .warmup {
                        Text("Working sets").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    SwipeToDelete(action: { variant.sets.removeAll { $0.id == plan.id } }) { row(plan, index: index, weight: weights[index]) }
                }
                let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                actions {
                    Button { addSet() } label: { Label("Add Set", systemImage: "plus") }.buttonStyle(FieldButtonStyle())
                    if exercise?.mode != .cardio {
                        Button("Drop") { technique = .drop }.buttonStyle(FieldButtonStyle(role: .technique))
                        Button("MYO") { technique = .myo }.buttonStyle(FieldButtonStyle(role: .technique))
                    }
                }
            }
        }.card(padding: 16)
        .sheet(item: $numberEdit) { NumberEditor(edit: $0) }
        .sheet(item: $repEdit) { plan in RepTargetEditor(plan: plan) { edited in update(plan.id) { $0.reps = edited.reps; $0.repCeiling = edited.repCeiling; $0.amrap = edited.amrap }; return true } }
        .sheet(item: $planEdit) { plan in
            TemplatePlanEditor(variant: variant, plan: plan) { edited in store.saveVariant(edited) }.sheetSize()
        }
        .sheet(isPresented: $settings) { VariantEditor(variant: variant).sheetSize() }
        .sheet(item: $technique) { kind in
            TechniqueEditor(kind: kind, workingWeight: variant.referenceWeight, rounding: variant.rounding) { plans, replace, _ in
                var edited = variant
                if replace { edited.sets.removeAll { $0.kind != .warmup } }
                if kind == .drop, let last = edited.sets.indices.last { edited.sets[last].restSeconds = 0 }
                edited.sets.append(contentsOf: plans); variant = edited
            }.sheetSize()
        }
    }

    private func row(_ plan: SetPlan, index: Int, weight: Double?) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Menu {
                ForEach(SetKind.allCases) { kind in
                    Button(kind.title) { update(plan.id) { $0.kind = kind; $0.customTypeID = nil; if kind == .warmup { $0.load = .percent } else if kind == .working { $0.load = .working } } }
                }
                if !store.data.customSetTypes.isEmpty {
                    Divider()
                    ForEach(store.data.customSetTypes) { type in
                        Button(type.name) { update(plan.id) { $0.kind = type.countsAs; $0.customTypeID = type.id } }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    SetBadge(text: setBadge(variant.sets, index: index, types: store.data.customSetTypes), plan: plan)
                    if plan.load == .percent { Text("\(number(plan.percent))%").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
            }.compactMenu().frame(width: 36, height: 44)
            field(exercise?.mode == .cardio ? plan.seconds.map(clockText) ?? "Time" : weight.map { number(unit.display($0)) } ?? "–", label: "Set \(index + 1), \(exercise?.mode == .cardio ? "time" : "weight")") {
                if exercise?.mode == .cardio {
                    numberEdit = NumericEdit(title: "Time (minutes)", value: plan.seconds.map { $0 / 60 }, step: 1, maximum: 100000, integer: false) { value in update(plan.id) { $0.seconds = value.map { $0 * 60 } } }
                } else { editWeight(plan) }
            }
            .contextMenu {
                Button("Use Suggested Weight") { update(plan.id) { $0.load = .working; $0.weightOverride = nil } }
                Button("Use Separate Weight") { update(plan.id) { $0.fixedWeight = weight ?? 0; $0.load = .fixed }; editWeight(variant.sets.first { $0.id == plan.id } ?? plan) }
                if plan.kind == .warmup || plan.kind == .drop { Button("Use Percentage") { update(plan.id) { $0.load = .percent } } }
            }
            field(plan.repTarget ?? "–", label: "Set \(index + 1), rep target") { repEdit = plan }
            field(plan.rpe.map { number($0) } ?? "–", label: "Set \(index + 1), RPE") {
                numberEdit = NumericEdit(title: "RPE", value: plan.rpe, step: 0.5, maximum: 10, integer: false) { value in update(plan.id) { $0.rpe = value } }
            }.frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 50)
        }
        .contextMenu { Button("More Targets") { planEdit = plan }; Button("Delete Set", role: .destructive) { variant.sets.removeAll { $0.id == plan.id } } }
    }

    private func field(_ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 3) { if typeSize.isAccessibilitySize { Text(label).font(.caption).foregroundStyle(.secondary) }; Text(value).font(.figure(17)) }.frame(maxWidth: .infinity, minHeight: 44).background(palette.field, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("\(label), \(value)")
    }
    private func update(_ id: UUID, _ change: (inout SetPlan) -> Void) {
        var edited = variant
        guard let index = edited.sets.firstIndex(where: { $0.id == id }) else { return }
        change(&edited.sets[index]); variant = edited
    }
    private func editWeight(_ plan: SetPlan) {
        if plan.load == .working {
            numberEdit = NumericEdit(title: "Weight (\(unit.rawValue))", context: exercise?.name, value: unit.display(variant.weight(for: plan) ?? 0), step: 2.5, maximum: 100000, integer: false) { value in
                variant.setWeight(unit.kilograms(value ?? 0), for: plan.id)
            }
            return
        }
        let percent = plan.load == .percent
        numberEdit = NumericEdit(title: percent ? "% of working weight" : "Weight (\(unit.rawValue))", context: exercise?.name, value: percent ? plan.percent : unit.display(plan.fixedWeight), step: percent ? 5 : 2.5, maximum: percent ? 1000 : 100000, integer: false) { value in
            update(plan.id) { if percent { $0.percent = value ?? 0 } else { $0.load = .fixed; $0.fixedWeight = unit.kilograms(value ?? 0) } }
        }
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
