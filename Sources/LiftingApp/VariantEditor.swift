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
                Section("Variant") {
                    Text(exercise?.name ?? "Exercise").font(.headline)
                    TextField("Variant name", text: $variant.label)
                }
                Section("Load and rest") {
                    HStack { Text("Working weight (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.workingWeight) }, set: { variant.workingWeight = unit.kilograms($0) }), format: .number).multilineTextAlignment(.trailing).frame(maxWidth: 110) }
                    HStack { Text("Rounding down (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.rounding) }, set: { variant.rounding = unit.kilograms($0) }), format: .number).multilineTextAlignment(.trailing).frame(maxWidth: 110) }
                    Stepper("Rest: \(clockText(Double(variant.restSeconds)))", value: $variant.restSeconds, in: 0...3600, step: 15)
                }
                Section("Sets") {
                    ForEach($variant.sets) { $plan in
                        NavigationLink { PlanEditor(plan: $plan, unit: unit) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.kind.title).font(.headline)
                                Text(setPlanSummary(plan, unit: unit)).font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                        .contextMenu {
                            Button("Duplicate") { var copy = plan; copy.id = UUID(); if let i = variant.sets.firstIndex(where: { $0.id == plan.id }) { variant.sets.insert(copy, at: i + 1) } }
                            Button("Delete", role: .destructive) { variant.sets.removeAll { $0.id == plan.id } }
                        }
                    }
                    .onDelete { variant.sets.remove(atOffsets: $0) }
                    .onMove { variant.sets.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        Button("Working set") { variant.sets.append(SetPlan(load: exercise?.mode == .strength ? .working : .none, reps: exercise?.mode == .cardio ? nil : 8, repCeiling: exercise?.mode == .cardio ? nil : 12, seconds: exercise?.mode == .cardio ? 1200 : nil)) }
                        Button("Warm-up set") { variant.sets.insert(SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil), at: 0) }
                        Button("Drop sets") { technique = .drop }.disabled(exercise?.mode == .cardio)
                        Button("MYO reps") { technique = .myo }.disabled(exercise?.mode == .cardio)
                    } label: { Label("Add sets", systemImage: "plus") }
                    Menu("Warm-up presets") {
                        ForEach(store.data.warmupPresets) { preset in Button(preset.name) { variant.sets = TrainingData.applyingWarmups(preset.sets, to: variant.sets, replacing: true) } }
                        Button("50% × 8, 70% × 5, 85% × 2") { variant.sets.removeAll { $0.kind == .warmup }; variant.sets.insert(contentsOf: [(50.0, 8), (70.0, 5), (85.0, 2)].map { SetPlan(kind: .warmup, load: .percent, percent: $0.0, reps: $0.1, repCeiling: nil) }, at: 0) }
                        Button("Save current warm-ups as preset") { savingWarmups = true }.disabled(!variant.sets.contains { $0.kind == .warmup })
                        Button("Remove warm-ups") { variant.sets.removeAll { $0.kind == .warmup } }
                    }
                }
                Section("Progression") {
                    Picker("Rule", selection: $variant.progression.mode) { ForEach(ProgressionMode.allCases) { Text($0.title).tag($0) } }
                    if variant.progression.mode != .manual {
                        HStack { Text("Increase (\(unit.rawValue))"); Spacer(); TextField("0", value: Binding(get: { unit.display(variant.progression.increment) }, set: { variant.progression.increment = unit.kilograms($0) }), format: .number).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                        Stepper("Deload after \(variant.progression.deloadAfter) misses", value: $variant.progression.deloadAfter, in: 0...10)
                        HStack { Text("Deload %"); TextField("10", value: $variant.progression.deloadPercent, format: .number).multilineTextAlignment(.trailing) }
                        Text(variant.progression.mode == .double ? "Adds weight next time when every working set reaches the top of its rep range." : "Adds weight next time when every working set reaches its target reps.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Recurring note") { TextField("Note for this variant", text: $variant.notes, axis: .vertical).lineLimit(3...8) }
                if let validationError { Text(validationError).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("Prescription").inlineTitle()
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
    if let rest = plan.restSeconds { parts.append("\(rest)s rest") }
    return parts.joined(separator: " · ")
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
                if live { Section { Toggle("Save to this day variant", isOn: $saveFuture) } }
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
