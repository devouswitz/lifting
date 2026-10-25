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
                DurationRow("Rest", seconds: $plan.restSeconds, placeholder: "Exercise default").accessibilityIdentifier("plan.rest")
            }
            if let loggedSet {
                Section("Logged Values") {
                    DurationRow(title: "Time", seconds: loggedSet.seconds)
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
        _repSelection = State(initialValue: RepTargetMode(plan.wrappedValue))
    }
    var body: some View {
        Picker("Rep target", selection: repMode) { ForEach(RepTargetMode.allCases) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("plan.repMode")
        switch repSelection {
        case .none: EmptyView()
        case .exact, .range:
            NumberRow(repSelection == .range ? "Minimum reps" : "Target reps", value: Binding(get: { plan.reps ?? 8 }, set: {
                plan.reps = $0
                if repSelection == .exact { plan.repCeiling = nil }
            })).accessibilityIdentifier("plan.reps")
            if repSelection == .range {
                NumberRow("Maximum reps", value: Binding(get: { plan.repCeiling ?? 12 }, set: { plan.repCeiling = $0 })).accessibilityIdentifier("plan.repCeiling")
            }
        case .amrap:
            NumberRow("Goal reps", value: Binding(get: { plan.reps.map(Double.init) }, set: { plan.reps = $0.map { Int($0) } }), placeholder: "None", integer: true).accessibilityIdentifier("plan.reps")
        }
    }
    private var repMode: Binding<RepTargetMode> {
        Binding(get: { repSelection }, set: { mode in
            repSelection = mode
            plan.amrap = mode == .amrap
            switch mode {
            case .none: plan.reps = nil; plan.repCeiling = nil
            case .exact: plan.reps = plan.reps ?? 8; plan.repCeiling = nil
            case .range: plan.reps = plan.reps ?? 8; plan.repCeiling = max((plan.reps ?? 8) + 1, plan.repCeiling ?? 12)
            case .amrap: plan.repCeiling = nil
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
                DurationRow(title: "Time", seconds: $plan.seconds).accessibilityIdentifier("plan.seconds")
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
    case none = "No count", exact = "Reps", range = "Rep range", amrap = "AMRAP"
    var id: Self { self }
    init(_ plan: SetPlan) { self = plan.amrap ? .amrap : plan.reps == nil ? .none : plan.repRange == nil ? .exact : .range }
}

func setPlanSummary(_ plan: SetPlan, unit: WeightUnit) -> String {
    var parts: [String] = []
    switch plan.load { case .percent: parts.append("\(number(plan.percent))% of working set"); case .fixed: parts.append("\(number(unit.display(plan.fixedWeight))) \(unit.rawValue)"); case .working: parts.append("Working weight"); case .none: break }
    if let target = plan.repTarget { parts.append(plan.amrap && plan.reps == nil ? target : "\(displayTarget(target)) reps") }
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
    if let target = plan.repTarget.map(displayTarget) { parts.append(load.isEmpty ? (plan.amrap && plan.reps == nil ? target : "\(target) reps") : "\(load) × \(target)") }
    else if !load.isEmpty { parts.append(load) }
    if let seconds = plan.seconds { parts.append(clockText(seconds)) }
    if let meters = plan.meters { parts.append("\(number(meters)) m") }
    if let rpe = plan.rpe { parts.append("RPE \(number(rpe))") }
    if let rest = plan.restSeconds { parts.append(rest == 0 ? "no rest" : "\(clockText(Double(rest))) rest") }
    return parts.isEmpty ? "No targets" : parts.joined(separator: " · ")
}

/// Drop and MYO setup. Applying adds the chain; the setup can be kept for this exercise or every exercise.
/// Without an apply action it edits the app-wide defaults.
struct TechniqueEditor: View {
    @EnvironmentObject var store: AppStore
    let technique: Technique
    var exerciseID: UUID? = nil
    var live = false
    var onAdd: (([SetPlan], Bool, Bool) -> Bool)? = nil
    @State private var setup = TechniqueDefaults()
    @State private var initial: TechniqueDefaults?
    @State private var replace = false
    @State private var saveFuture = false
    @State private var remember = Remember.no
    private enum Remember: Hashable { case no, exercise, everywhere }
    private var exercise: Exercise? { exerciseID.flatMap(store.data.exercise) }
    var body: some View {
        DraftEditor(valid: setup.isValid, changed: initial.map { $0 != setup } == true || replace || saveFuture || remember != .no,
                    saveID: "technique.add", confirmation: onAdd == nil ? nil : "Apply", save: save) {
            ThemedForm {
                if technique == .drop {
                    Section {
                        IntegerControl(title: "Drops", value: $setup.dropCount, range: 1...10)
                        PercentControl(title: "Reduce each drop (%)", value: $setup.dropPercent, range: 0...100)
                    }
                    Section("Drop targets") { SetTargetFields(plan: $setup.drop) }
                } else {
                    Section("Activation") { SetTargetFields(plan: $setup.activation) }
                    Section("Mini-sets") {
                        IntegerControl(title: "Mini-sets", value: $setup.miniCount, range: 1...20)
                        DurationRow("Rest between", seconds: $setup.myoRest, presets: [10, 15, 20, 30])
                        SetTargetFields(plan: $setup.mini)
                    }
                }
                if onAdd != nil {
                    Section {
                        if technique == .myo { Toggle(live ? "Replace remaining work sets" : "Replace working sets", isOn: $replace) }
                        if live { Toggle("Save to this day", isOn: $saveFuture) }
                        Picker("Keep this setup", selection: $remember) {
                            Text("This time only").tag(Remember.no)
                            if let exercise { Text("For \(exercise.name)").tag(Remember.exercise) }
                            Text("For all exercises").tag(Remember.everywhere)
                        }
                        if exercise?.techniques != nil {
                            Button("Use App Defaults") {
                                if store.perform({ d in if let i = d.exercises.firstIndex(where: { $0.id == exerciseID }) { d.exercises[i].techniques = nil } }) {
                                    setup = store.data.techniqueDefaults(for: exerciseID); initial = setup
                                }
                            }
                        }
                    }
                    Section("Preview") {
                        ForEach(setup.plans(technique)) { plan in
                            VStack(alignment: .leading, spacing: 5) { Text(plan.kind.title).font(.headline); Text(setPlanSummary(plan, unit: store.data.settings.unit)).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                } else {
                    Section { Button("Restore Standard Setup") { setup = TechniqueDefaults() }.disabled(setup == TechniqueDefaults()) }
                }
            }.formStyle(.grouped).navigationTitle(technique.title).inlineTitle()
        }.onAppear {
            guard initial == nil else { return }
            setup = onAdd == nil ? store.data.settings.techniques ?? TechniqueDefaults() : store.data.techniqueDefaults(for: exerciseID)
            initial = setup
        }
    }
    private func save() -> Bool {
        guard let onAdd else { return store.perform { $0.settings.techniques = setup } }
        guard onAdd(setup.plans(technique), replace, saveFuture) else { return false }
        guard remember != .no else { return true }
        return store.perform { data in
            let index = data.exercises.firstIndex { $0.id == exerciseID }
            if remember == .everywhere { data.settings.techniques = setup }
            if let index { data.exercises[index].techniques = remember == .exercise ? setup : nil }
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
