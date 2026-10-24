import SwiftUI
import LiftingCore

struct VariantEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    @State var variant: Variant
    @State private var technique: TechniqueKind?
    @State private var validationError: String?
    @State private var savingWarmups = false
    var unit: WeightUnit { store.data.settings.unit }
    var exercise: Exercise? { store.data.exercise(variant.exerciseID) }
    var body: some View {
        NavigationStack {
            let weights = variant.resolvedWeights
            ThemedForm {
                Section("Load and rest") {
                    if exercise?.mode != .cardio {
                        LabeledContent("Working sets", value: weightSummary(variant.resolvedWeights.enumerated().compactMap { variant.sets[$0.offset].kind == .warmup ? nil : $0.element }, unit: unit))
                        NumberRow("Round % weights down to (\(unit.rawValue))", value: $variant.rounding, factor: unit.kilograms(1))
                    }
                    Stepper("Rest between sets: \(clockText(Double(variant.restSeconds)))", value: $variant.restSeconds, in: 0...3600, step: 15)
                }
                Section("Sets") {
                    ForEach(Array($variant.sets.enumerated()), id: \.element.id) { index, $plan in
                        NavigationLink { PlanEditor(plan: $plan, unit: unit, suggestedWeight: weights[index]) } label: {
                            HStack(spacing: 12) {
                                SetBadge(text: setBadge(variant.sets, index: index, types: store.data.customSetTypes), plan: plan).frame(minWidth: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prescribedSetSummary(plan, weight: weights[index], unit: unit)).font(.subheadline).monospacedDigit()
                                    if plan.customTypeID != nil || ![.warmup, .working].contains(plan.kind) { Text(palette.title(plan)).font(.caption).foregroundStyle(palette.color(for: plan)) }
                                }
                            }.padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button("Duplicate") { var copy = plan; copy.id = UUID(); if let i = variant.sets.firstIndex(where: { $0.id == plan.id }) { variant.sets.insert(copy, at: i + 1) } }
                            Button("Delete", role: .destructive) { variant.sets.removeAll { $0.id == plan.id } }
                        }
                    }
                    .onDelete { variant.sets.remove(atOffsets: $0) }
                    .onMove { variant.sets.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        Button(exercise?.mode == .cardio ? "Interval" : "Working Set") { addWorkingSet() }
                        if exercise?.mode != .cardio {
                            Button("Warm-up Set") { addWarmup() }
                            Button("Drop Sets") { technique = .drop }
                            Button("MYO Reps") { technique = .myo }
                            Button("Failure Set") { addTyped(kind: .failure) }
                            if !store.data.customSetTypes.isEmpty {
                                Divider()
                                ForEach(store.data.customSetTypes) { type in Button(type.name) { addTyped(kind: type.countsAs, customTypeID: type.id) } }
                            }
                        }
                    } label: { Label("Add Sets", systemImage: "plus") }
                    if exercise?.mode != .cardio { Menu {
                        ForEach(store.data.warmupPresets) { preset in Button(preset.name) { variant.sets = TrainingData.applyingWarmups(preset.sets, to: variant.sets, replacing: true) } }
                        Button("50% × 8, 70% × 5, 85% × 2") { variant.sets.removeAll { $0.kind == .warmup }; variant.sets.insert(contentsOf: [(50.0, 8), (70.0, 5), (85.0, 2)].map { SetPlan(kind: .warmup, load: .percent, percent: $0.0, reps: $0.1, repCeiling: nil) }, at: 0) }
                        Button("Save current warm-ups as preset") { savingWarmups = true }.disabled(!variant.sets.contains { $0.kind == .warmup })
                        Button("Remove warm-ups", role: .destructive) { variant.sets.removeAll { $0.kind == .warmup } }.disabled(!variant.sets.contains { $0.kind == .warmup })
                    } label: { Label("Warm-up Presets", systemImage: "flame") } }
                }
                Section("Progression") {
                    Picker("Rule", selection: $variant.progression.mode) { ForEach(ProgressionMode.allCases) { Text($0.title).tag($0) } }
                    if variant.progression.mode != .manual {
                        NumberRow("Increase (\(unit.rawValue))", value: $variant.progression.increment, factor: unit.kilograms(1))
                        Stepper(variant.progression.deloadAfter == 0 ? "Never deload" : "Deload after \(counted(variant.progression.deloadAfter, "miss"))", value: $variant.progression.deloadAfter, in: 0...10)
                        if variant.progression.deloadAfter > 0 { NumberRow("Deload by (%)", value: $variant.progression.deloadPercent) }
                        Text(variant.progression.mode == .double ? "Adds weight next time when every working set reaches the top of its rep range." : "Adds weight next time when every working set reaches its target reps.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent("Track") { TextField("Track name", text: $variant.label).multilineTextAlignment(.trailing) }
                } footer: { Text("Progress keeps each track separate.") }
                Section("Note shown every session") { TextField("Optional", text: $variant.notes, axis: .vertical).lineLimit(3...8) }
                if let validationError { Text(validationError).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle(exercise?.name ?? "Prescription").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    var check = store.data
                    if let i = check.variants.firstIndex(where: { $0.id == variant.id }) { check.variants[i] = variant }
                    else { check.variants.append(variant) }
                    do { _ = try check.validated(); if store.saveVariant(variant) { dismiss() } } catch { validationError = error.localizedDescription }
                }.disabled(variant.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || variant.sets.isEmpty) }
            }
            .sheet(item: $technique) { kind in TechniqueEditor(kind: kind, workingWeight: variant.referenceWeight, rounding: variant.rounding) { plans, replace, _ in
                if replace { variant.sets.removeAll { $0.kind != .warmup } }
                if kind == .drop, let last = variant.sets.indices.last { variant.sets[last].restSeconds = 0 }
                variant.sets.append(contentsOf: plans)
            }.sheetSize() }
            .sheet(isPresented: $savingWarmups) { WarmupPresetEditor(preset: WarmupPreset(name: variant.label + " warm-up", sets: variant.sets.filter { $0.kind == .warmup })).environmentObject(store).sheetSize() }
        }
    }
}

extension VariantEditor {
    /// Copies the last working set so a new set keeps this exercise's targets.
    func addWorkingSet() {
        if var copy = variant.sets.last(where: { $0.kind != .warmup }) {
            copy.id = UUID(); copy.weightOverride = nil; if [.drop, .myoActivation, .myoMini].contains(copy.kind) { copy.kind = .working; copy.load = exercise?.mode == .strength ? .working : .none; copy.restSeconds = nil }
            variant.sets.append(copy)
        } else if let exercise {
            var plan = Variant.standard(for: exercise, label: "").sets[0]; plan.id = UUID(); variant.sets.append(plan)
        }
    }
    /// Adds a set of a kind or custom type, copying the last working set's targets.
    func addTyped(kind: SetKind, customTypeID: UUID? = nil) {
        if kind == .warmup { addWarmup(); if let i = variant.sets.lastIndex(where: { $0.kind == .warmup }) { variant.sets[i].customTypeID = customTypeID }; return }
        addWorkingSet()
        guard let last = variant.sets.indices.last else { return }
        variant.sets[last].kind = kind; variant.sets[last].customTypeID = customTypeID
    }
    /// Adds a warm-up after the existing warm-ups, matching the live workout's Add Warm-up Set.
    func addWarmup() {
        let position = (variant.sets.lastIndex { $0.kind == .warmup }).map { $0 + 1 } ?? 0
        variant.sets.insert(SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil), at: position)
    }
}

struct PlanEditor: View {
    @Environment(\.palette) var palette
    @Binding var plan: SetPlan
    let unit: WeightUnit
    var suggestedWeight: Double? = nil
    var warmupOnly = false
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            if !warmupOnly { Section("Set") {
                Picker("Type", selection: typeChoice) {
                    ForEach(SetKind.allCases) { Text($0.title).tag(SetTypeChoice.kind($0)) }
                    ForEach(palette.setTypes) { Text($0.name).tag(SetTypeChoice.custom($0.id)) }
                }
            } }
            Section(plan.kind == .warmup ? "Warm-up weight" : "Weight") {
                Picker("Based on", selection: $plan.load) { ForEach(loadRules) { Text($0.title).tag($0) } }
                if plan.load == .working {
                    NumberRow("Weight (\(unit.rawValue))", value: Binding(get: { plan.weightOverride ?? suggestedWeight }, set: { plan.weightOverride = $0 }), placeholder: "Suggested", factor: unit.kilograms(1))
                }
                if plan.load == .percent { PercentControl(title: "Percent of working set", value: $plan.percent, range: 0...1000) }
                if plan.load == .fixed { NumberRow("Weight (\(unit.rawValue))", value: $plan.fixedWeight, factor: unit.kilograms(1)) }
            }
            Section("Targets") {
                SetTargetFields(plan: $plan)
            }
            Section("Rest after this set") {
                NumberRow("Rest in seconds", value: Binding(get: { plan.restSeconds.map(Double.init) }, set: { plan.restSeconds = $0.map { Int($0) } }), placeholder: "Exercise default", integer: true).accessibilityIdentifier("plan.rest")
            }
        }.formStyle(.grouped).navigationTitle(palette.title(plan)).inlineTitle()
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
    }
}

/// A built-in kind or a custom type, as one picker value.
enum SetTypeChoice: Hashable { case kind(SetKind), custom(UUID) }

extension PlanEditor {
    var loadRules: [LoadRule] { LoadRule.allCases }
    var typeChoice: Binding<SetTypeChoice> {
        Binding(get: { plan.customTypeID.flatMap { id in palette.setTypes.contains { $0.id == id } ? .custom(id) : nil } ?? .kind(plan.kind) }, set: { choice in
            switch choice {
            case .kind(let kind): plan.kind = kind; plan.customTypeID = nil
            case .custom(let id): plan.customTypeID = id; plan.kind = palette.setTypes.first { $0.id == id }?.countsAs ?? .working
            }
        })
    }
}

struct RepTargetFields: View {
    @Binding var plan: SetPlan
    @State private var repSelection: RepTargetMode
    init(plan: Binding<SetPlan>) {
        _plan = plan
        _repSelection = State(initialValue: plan.wrappedValue.reps == nil ? .none : plan.wrappedValue.repRange == nil ? .exact : .range)
    }
    var body: some View {
        Group {
                Picker("Rep target", selection: repMode) { ForEach(RepTargetMode.allCases) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("plan.repMode")
                if repSelection != .none {
                    NumberRow(repSelection == .range ? "Minimum reps" : "Target reps", value: Binding(get: { plan.reps ?? 8 }, set: {
                        plan.reps = $0
                        if repSelection == .exact { plan.repCeiling = nil }
                    })).accessibilityIdentifier("plan.reps")
                    if repSelection == .range {
                        NumberRow("Maximum reps", value: Binding(get: { plan.repCeiling ?? 12 }, set: { plan.repCeiling = $0 })).accessibilityIdentifier("plan.repCeiling")
                    }
                    Toggle("AMRAP", isOn: $plan.amrap)
                }

        }
    }
    private var repMode: Binding<RepTargetMode> {
        Binding(get: { repSelection }, set: { mode in
            repSelection = mode
            switch mode {
            case .none: plan.reps = nil; plan.repCeiling = nil; plan.amrap = false
            case .exact: plan.reps = plan.reps ?? 8; plan.repCeiling = nil
            case .range: plan.reps = plan.reps ?? 8; plan.repCeiling = max((plan.reps ?? 8) + 1, plan.repCeiling ?? 12)
            }
        })
    }
}

struct SetTargetFields: View {
    @Binding var plan: SetPlan
    var body: some View {
        Group {
            RepTargetFields(plan: $plan)
                NumberRow("RPE", value: $plan.rpe).accessibilityIdentifier("plan.rpe")
                NumberRow("Time (minutes)", value: $plan.seconds, factor: 60).accessibilityIdentifier("plan.seconds")
                NumberRow("Distance (meters)", value: $plan.meters).accessibilityIdentifier("plan.meters")
        }
    }
}

struct RepTargetEditor: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @State var plan: SetPlan
    let onSave: (SetPlan) -> Bool
    var body: some View {
        NavigationStack {
            ThemedForm { Section { RepTargetFields(plan: $plan) } }
                .navigationTitle("Rep Target").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if onSave(plan) { dismiss() } }.disabled(!valid) }
                }
        }.frame(idealWidth: 440, idealHeight: 420)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(400), .large])
    }
    private var valid: Bool {
        (plan.reps.map { (0...10000).contains($0) } ?? true) && (plan.repCeiling.map { $0 >= (plan.reps ?? 0) && $0 <= 10000 } ?? true)
    }
}

private enum RepTargetMode: String, CaseIterable, Identifiable {
    case none = "No count", exact = "Reps", range = "Rep range"
    var id: Self { self }
}

func setPlanSummary(_ plan: SetPlan, unit: WeightUnit) -> String {
    var parts: [String] = []
    switch plan.load { case .percent: parts.append("\(number(plan.percent))% of working set"); case .fixed: parts.append("\(number(unit.display(plan.fixedWeight))) \(unit.rawValue)"); case .working: parts.append("Working weight"); case .none: break }
    if let reps = plan.reps { parts.append(plan.repCeiling != nil && plan.repCeiling != reps ? "\(reps)-\(plan.repCeiling!) reps" : "\(reps) reps") }
    if plan.amrap { parts.append("AMRAP") }
    if let seconds = plan.seconds { parts.append(clockText(seconds)) }
    if let meters = plan.meters { parts.append("\(number(meters)) m") }
    if let rpe = plan.rpe { parts.append("RPE \(number(rpe))") }
    if let rest = plan.restSeconds { parts.append(rest == 0 ? "no rest" : "\(clockText(Double(rest))) rest") }
    return parts.joined(separator: " · ")
}

/// Set summary with the load resolved against the variant's working weight, e.g. "47.5 lb (50%) × 5 · RPE 7".
func prescribedSetSummary(_ plan: SetPlan, weight: Double?, unit: WeightUnit) -> String {
    var load = ""
    if let weight {
        load = "\(number(unit.display(weight))) \(unit.rawValue)"
        if plan.load == .percent { load += " (\(number(plan.percent))%)" }
    }
    var parts: [String] = []
    if let target = plan.repTarget { parts.append(load.isEmpty ? "\(target) reps" : "\(load) × \(target)") }
    else if !load.isEmpty { parts.append(load) }
    if plan.amrap { parts.append("AMRAP") }
    if let seconds = plan.seconds { parts.append(clockText(seconds)) }
    if let meters = plan.meters { parts.append("\(number(meters)) m") }
    if let rpe = plan.rpe { parts.append("RPE \(number(rpe))") }
    if let rest = plan.restSeconds { parts.append(rest == 0 ? "no rest" : "\(clockText(Double(rest))) rest") }
    return parts.isEmpty ? "No targets" : parts.joined(separator: " · ")
}

enum TechniqueKind: String, Identifiable { case drop, myo; var id: String { rawValue }; var title: String { self == .drop ? "Drop sets" : "MYO reps" } }

struct TechniqueEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let kind: TechniqueKind
    let workingWeight: Double
    let rounding: Double
    var live = false
    var onAdd: ([SetPlan], Bool, Bool) -> Void
    @State private var reduction = 20.0
    @State private var dropCount = 1
    @State private var dropTarget = SetPlan(kind: .drop, reps: 10, repCeiling: nil)
    @State private var activationTarget = SetPlan(kind: .myoActivation, reps: 15, repCeiling: nil, rpe: 9, amrap: true)
    @State private var miniTarget = SetPlan(kind: .myoMini, reps: 5, repCeiling: nil)
    @State private var miniCount = 4
    @State private var rest = 20
    @State private var replace = true
    @State private var saveFuture = false
    var plans: [SetPlan] { kind == .drop ? SetTechniques.drops(workingWeight: workingWeight, rounding: rounding, reductionPercent: reduction, count: dropCount, reps: dropTarget.reps, repCeiling: dropTarget.repCeiling, rpe: dropTarget.rpe, seconds: dropTarget.seconds, meters: dropTarget.meters, amrap: dropTarget.amrap) : SetTechniques.myo(activation: activationTarget, mini: miniTarget, miniSets: miniCount, rest: rest) }
    private var validTargets: Bool {
        guard reduction.isFinite, (0...100).contains(reduction), (1...10).contains(dropCount), (1...20).contains(miniCount), (0...86400).contains(rest) else { return false }
        var data = TrainingData(); let exercise = Exercise(name: "Validation")
        data.exercises = [exercise]; data.variants = [Variant(exerciseID: exercise.id, label: "Validation", sets: plans)]
        return (try? data.validated()) != nil && plans.allSatisfy { $0.reps != nil || $0.rpe != nil || $0.seconds != nil || $0.meters != nil }
    }
    var body: some View {
        NavigationStack {
            ThemedForm {
                if kind == .drop {
                    Section {
                        IntegerControl(title: "Drops", value: $dropCount, range: 1...10)
                        PercentControl(title: "Reduce each drop (%)", value: $reduction, range: 0...100)
                    }
                    Section("Drop targets") {
                        SetTargetFields(plan: $dropTarget)
                    }
                } else {
                    Section("Activation") { SetTargetFields(plan: $activationTarget) }
                    Section("Mini-sets") {
                        IntegerControl(title: "Mini-sets", value: $miniCount, range: 1...20)
                        SetTargetFields(plan: $miniTarget)
                        IntegerControl(title: "Rest (seconds)", value: $rest, range: 0...86400, step: 5)
                    }
                    Toggle(live ? "Replace remaining work sets" : "Replace working sets", isOn: $replace)
                }
                if live { Section { Toggle("Save to this day", isOn: $saveFuture) } }
                Section("Preview") {
                    ForEach(plans) { plan in VStack(alignment: .leading, spacing: 5) { Text(plan.kind.title).font(.headline); Text(setPlanSummary(plan, unit: store.data.settings.unit)).font(.subheadline).foregroundStyle(.secondary) } }
                }
            }.formStyle(.grouped).navigationTitle(kind.title).inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { onAdd(plans, kind == .myo && replace, saveFuture); dismiss() }.disabled(!validTargets).accessibilityIdentifier("technique.add") }
            }
        }
    }
}

struct PercentControl: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var body: some View {
        HStack {
            NumberRow(title, value: $value)
            Stepper(title, value: $value, in: range, step: 5).labelsHidden().fixedSize()
        }
    }
}

struct IntegerControl: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var body: some View {
        HStack {
            NumberRow(title, value: $value)
            Stepper(title, value: $value, in: range, step: step).labelsHidden().fixedSize()
        }
    }
}
