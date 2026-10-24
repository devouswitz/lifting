import SwiftUI
import LiftingCore

/// Only exercise-plan configuration lives here; sets are edited in the primary card.
struct PlanSettingsEditor: View {
    @EnvironmentObject private var store: AppStore
    @State var variant: Variant
    private var unit: WeightUnit { store.data.settings.unit }
    private var valid: Bool {
        !variant.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && variant.label.count <= 200
            && variant.rounding.isFinite && variant.rounding >= 0
            && variant.progression.increment.isFinite && variant.progression.increment >= 0
            && (0...100).contains(variant.progression.deloadPercent)
    }
    var body: some View {
        DraftEditor(valid: valid, changed: store.data.variant(variant.id) != variant, save: {
            guard var current = store.data.variant(variant.id) else { return false }
            current.rounding = variant.rounding; current.progression = variant.progression; current.label = variant.label
            return store.saveVariant(current)
        }) {
            ThemedForm {
                Section("Progression") {
                    Picker("Rule", selection: $variant.progression.mode) { ForEach(ProgressionMode.allCases) { Text($0.title).tag($0) } }
                    if variant.progression.mode != .manual {
                        NumberRow("Increase (\(unit.rawValue))", value: $variant.progression.increment, factor: unit.kilograms(1))
                        Stepper(variant.progression.deloadAfter == 0 ? "Never deload" : "Deload after \(counted(variant.progression.deloadAfter, "miss"))", value: $variant.progression.deloadAfter, in: 0...10)
                        if variant.progression.deloadAfter > 0 { NumberRow("Deload by (%)", value: $variant.progression.deloadPercent) }
                    }
                }
                Section {
                    NumberRow("Round % weights down to (\(unit.rawValue))", value: $variant.rounding, factor: unit.kilograms(1))
                    LabeledContent("Track") { TextField("Track name", text: $variant.label).multilineTextAlignment(.trailing) }
                }
            }.navigationTitle("Plan Settings").inlineTitle()
        }
    }
}

/// The same saved-plan card remains available during a workout, with an explicit scope.
struct SavedExerciseEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let variantID: UUID
    @State private var expanded = true
    @State private var dragging: UUID?
    @State private var linking = false
    private var day: Routine? { store.data.routines.first { $0.slots.contains { $0.variantID == variantID } } }
    private var slot: RoutineSlot? { day?.slots.first { $0.variantID == variantID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let variant = store.data.variant(variantID) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(day?.name ?? variant.label).font(.subheadline).foregroundStyle(.secondary)
                        TemplateExerciseCard(
                            variant: Binding(get: { store.data.variant(variantID) ?? variant }, set: { store.saveVariant($0) }),
                            expanded: expanded, toggle: { expanded.toggle() },
                            link: day == nil ? nil : { linking = true }, move: { _ in },
                            canMoveUp: false, canMoveDown: false, slotID: slot?.id ?? variantID,
                            dragging: $dragging, remove: nil
                        )
                    }.padding(16)
                }
            }.navigationTitle("Saved Plan").inlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
                .sheet(isPresented: $linking) { LinkedExerciseEditor(routineID: day?.id, exerciseID: slot?.id).sheetSize() }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) var palette
    @Binding var plan: SetPlan
    let unit: WeightUnit
    var suggestedWeight: Double? = nil
    var warmupOnly = false
    var ownsDraft = true
    var loggedSet: Binding<LoggedSet>? = nil
    @State private var original: SetPlan?
    var body: some View {
        ThemedForm {
            StoreErrorRow()
            if !warmupOnly { Section("Set") {
                Picker("Type", selection: typeChoice) {
                    ForEach(SetKind.allCases) { Text($0.title).tag(SetTypeChoice.kind($0)) }
                    ForEach(palette.setTypes) { Text($0.name).tag(SetTypeChoice.custom($0.id)) }
                }
            } }
            SetLoadFields(plan: $plan, unit: unit, suggestedWeight: suggestedWeight)
            Section("Targets") {
                SetTargetFields(plan: $plan)
            }
            Section("Rest after this set") {
                NumberRow("Rest in seconds", value: Binding(get: { plan.restSeconds.map(Double.init) }, set: { plan.restSeconds = $0.map { Int($0) } }), placeholder: "Exercise default", integer: true).accessibilityIdentifier("plan.rest")
            }
            if let loggedSet {
                Section("Logged Values") {
                    NumberRow("Time (minutes)", value: loggedSet.seconds, factor: 60)
                    NumberRow("Distance (meters)", value: loggedSet.meters)
                }
            }
        }.formStyle(.grouped).navigationTitle(palette.title(plan)).inlineTitle()
        .toolbar {
            if ownsDraft {
                if !plan.isValid {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if let original { plan = original }; dismiss() } }
                }
            }
        }
        .onAppear { if original == nil { original = plan } }
        .navigationBarBackButtonHidden(!plan.isValid)
        .interactiveDismissDisabled(!plan.isValid)
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
    }
}

/// A built-in kind or a custom type, as one picker value.
enum SetTypeChoice: Hashable { case kind(SetKind), custom(UUID) }

extension PlanEditor {
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
    @State var plan: SetPlan
    let onSave: (SetPlan) -> Bool
    @State private var original: SetPlan?
    var body: some View {
        DraftEditor(valid: plan.isValid, changed: original.map { $0 != plan } ?? false, save: { onSave(plan) }) {
            ThemedForm { Section { RepTargetFields(plan: $plan) } }
                .navigationTitle("Rep Target").inlineTitle()
        }.frame(idealWidth: 440, idealHeight: 420)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(400), .large])
        .onAppear { if original == nil { original = plan } }
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
    var onAdd: ([SetPlan], Bool, Bool) -> Bool
    @State private var reduction = 20.0
    @State private var dropCount = 1
    @State private var dropTarget = SetPlan(kind: .drop, reps: 10, repCeiling: nil)
    @State private var activationTarget = SetPlan(kind: .myoActivation, reps: 15, repCeiling: nil, rpe: 9, amrap: true)
    @State private var miniTarget = SetPlan(kind: .myoMini, reps: 5, repCeiling: nil)
    @State private var miniCount = 4
    @State private var rest = 20
    @State private var replace = true
    @State private var saveFuture = false
    @State private var initialTargets: [SetPlan]?
    var plans: [SetPlan] { kind == .drop ? SetTechniques.drops(workingWeight: workingWeight, rounding: rounding, reductionPercent: reduction, count: dropCount, reps: dropTarget.reps, repCeiling: dropTarget.repCeiling, rpe: dropTarget.rpe, seconds: dropTarget.seconds, meters: dropTarget.meters, amrap: dropTarget.amrap) : SetTechniques.myo(activation: activationTarget, mini: miniTarget, miniSets: miniCount, rest: rest) }
    private var validTargets: Bool {
        guard reduction.isFinite, (0...100).contains(reduction), (1...10).contains(dropCount), (1...20).contains(miniCount), (0...86400).contains(rest) else { return false }
        var data = TrainingData(); let exercise = Exercise(name: "Validation")
        data.exercises = [exercise]; data.variants = [Variant(exerciseID: exercise.id, label: "Validation", sets: plans)]
        return (try? data.validated()) != nil && plans.allSatisfy { $0.reps != nil || $0.rpe != nil || $0.seconds != nil || $0.meters != nil }
    }
    var body: some View {
        DraftEditor(valid: validTargets, changed: initialTargets.map { $0 != [dropTarget, activationTarget, miniTarget] } == true || reduction != 20 || dropCount != 1 || miniCount != 4 || rest != 20 || !replace || saveFuture, saveID: "technique.add", confirmation: "Apply", save: {
            onAdd(plans, kind == .myo && replace, saveFuture)
        }) {
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
        }.onAppear { if initialTargets == nil { initialTargets = [dropTarget, activationTarget, miniTarget] } }
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
