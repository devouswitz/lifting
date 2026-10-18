import SwiftUI
import LiftingCore

struct VariantEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var variant: Variant
    @State private var technique: TechniqueKind?
    @State private var validationError: String?
    @State private var savingWarmups = false
    var unit: WeightUnit { store.data.settings.unit }
    var exercise: Exercise? { store.data.exercise(variant.exerciseID) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Track name", text: $variant.label)
                } header: { Text("Track") }
                Section("Load and rest") {
                    if exercise?.mode != .cardio {
                        HStack { Text("Working weight (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.workingWeight) }, set: { variant.workingWeight = unit.kilograms($0) }), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 110) }
                        HStack { Text("Round % weights down to (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.rounding) }, set: { variant.rounding = unit.kilograms($0) }), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 80) }
                    }
                    Stepper("Rest between sets: \(clockText(Double(variant.restSeconds)))", value: $variant.restSeconds, in: 0...3600, step: 15)
                }
                Section("Sets") {
                    ForEach(Array($variant.sets.enumerated()), id: \.element.id) { index, $plan in
                        NavigationLink { PlanEditor(plan: $plan, unit: unit) } label: {
                            HStack(spacing: 12) {
                                Text(setBadge(variant.sets.map(\.kind), index: index)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prescribedSetSummary(plan, variant: variant, unit: unit)).font(.subheadline).monospacedDigit()
                                    if ![.warmup, .working].contains(plan.kind) { Text(plan.kind.title).font(.caption).foregroundStyle(.secondary) }
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
                        HStack { Text("Increase (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.progression.increment) }, set: { variant.progression.increment = unit.kilograms($0) }), format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                        Stepper(variant.progression.deloadAfter == 0 ? "Never deload" : "Deload after \(counted(variant.progression.deloadAfter, "miss"))", value: $variant.progression.deloadAfter, in: 0...10)
                        if variant.progression.deloadAfter > 0 { HStack { Text("Deload by (%)"); Spacer(); TextField("10", value: $variant.progression.deloadPercent, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 80) } }
                        Text(variant.progression.mode == .double ? "Adds weight next time when every working set reaches the top of its rep range." : "Adds weight next time when every working set reaches its target reps.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
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
            .sheet(item: $technique) { kind in TechniqueEditor(kind: kind, workingWeight: variant.workingWeight, rounding: variant.rounding) { plans, replace, _ in
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
            copy.id = UUID(); if [.drop, .myoActivation, .myoMini].contains(copy.kind) { copy.kind = .working; copy.load = exercise?.mode == .strength ? .working : .none; copy.restSeconds = nil }
            variant.sets.append(copy)
        } else if let exercise {
            var plan = Variant.standard(for: exercise, label: "").sets[0]; plan.id = UUID(); variant.sets.append(plan)
        }
    }
    /// Adds a warm-up after the existing warm-ups, matching the live workout's Add Warm-up Set.
    func addWarmup() {
        let position = (variant.sets.lastIndex { $0.kind == .warmup }).map { $0 + 1 } ?? 0
        variant.sets.insert(SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil), at: position)
    }
}

struct PlanEditor: View {
    @Binding var plan: SetPlan
    let unit: WeightUnit
    var warmupOnly = false
    var body: some View {
        Form {
            StoreErrorRow()
            if !warmupOnly { Section("Set") {
                Picker("Type", selection: $plan.kind) { ForEach(SetKind.allCases) { Text($0.title).tag($0) } }
            } }
            Section(plan.kind == .warmup ? "Warm-up weight" : "Weight") {
                Picker("Based on", selection: $plan.load) { ForEach(LoadRule.allCases) { Text($0.title).tag($0) } }
                if plan.load == .percent { PercentControl(title: "Percent of working set", value: $plan.percent, range: 0...1000) }
                if plan.load == .fixed { HStack { Text("Weight (\(unit.rawValue))"); TextField("0", value: Binding(get: { unit.display(plan.fixedWeight) }, set: { plan.fixedWeight = unit.kilograms($0) }), format: .number).multilineTextAlignment(.trailing).labelsHidden() } }
            }
            Section("Targets") {
                SetTargetFields(plan: $plan)
            }
            Section("Rest after this set") {
                HStack { Text("Seconds"); OptionalNumberField(title: "Exercise default", value: Binding(get: { plan.restSeconds.map(Double.init) }, set: { plan.restSeconds = $0.map { Int($0) } }), integer: true).labelsHidden().accessibilityLabel("Rest in seconds").accessibilityIdentifier("plan.rest") }
            }
        }.formStyle(.grouped).navigationTitle(plan.kind.title).inlineTitle()
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
    }
}

struct SetTargetFields: View {
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
                    HStack { Text(repSelection == .range ? "Minimum reps" : "Target reps"); TextField("Reps", value: Binding(get: { plan.reps ?? 8 }, set: { plan.reps = $0 }), format: .number).multilineTextAlignment(.trailing).labelsHidden().accessibilityLabel("Target reps").accessibilityIdentifier("plan.reps") }
                    if repSelection == .range {
                        HStack { Text("Maximum reps"); TextField("Reps", value: Binding(get: { plan.repCeiling ?? 12 }, set: { plan.repCeiling = $0 }), format: .number).multilineTextAlignment(.trailing).labelsHidden().accessibilityLabel("Maximum reps").accessibilityIdentifier("plan.repCeiling") }
                    }
                    Toggle("AMRAP", isOn: $plan.amrap)
                }
                HStack { Text("RPE"); OptionalNumberField(title: "Optional", value: $plan.rpe).labelsHidden().accessibilityLabel("RPE").accessibilityIdentifier("plan.rpe") }
                HStack { Text("Time (minutes)"); OptionalNumberField(title: "Optional", value: $plan.seconds, factor: 60).labelsHidden().accessibilityLabel("Time in minutes").accessibilityIdentifier("plan.seconds") }
                HStack { Text("Distance (meters)"); OptionalNumberField(title: "Optional", value: $plan.meters).labelsHidden().accessibilityLabel("Distance in meters").accessibilityIdentifier("plan.meters") }
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
func prescribedSetSummary(_ plan: SetPlan, variant: Variant, unit: WeightUnit) -> String {
    var load = ""
    if let weight = plan.resolvedWeight(working: variant.workingWeight, increment: variant.rounding) {
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
            Form {
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
            Text(title)
            Spacer()
            TextField("%", value: $value, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 70)
                .accessibilityLabel(title).accessibilityIdentifier("plan.percent")
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
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
            Text(title); Spacer()
            TextField("0", value: $value, format: .number).labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 70).accessibilityLabel(title)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Stepper(title, value: $value, in: range, step: step).labelsHidden().fixedSize()
        }
    }
}
