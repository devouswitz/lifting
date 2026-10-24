import SwiftUI
import LiftingCore

struct LiveSetRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.palette) var palette
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    let setID: UUID
    let index: Int
    @State private var edit: NumericEdit?
    @State private var editingReps = false
    @State private var editingDetails = false
    @State private var editingLoad = false
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var set: LoggedSet? { item?.sets.first { $0.id == setID } }
    var previous: LoggedSet? {
        guard let item, let set else { return nil }
        let sets = store.previousSets(for: item.variantID).filter { $0.plan.kind == set.plan.kind }
        let ordinal = item.sets.prefix(index).filter { $0.plan.kind == set.plan.kind }.count
        if sets.indices.contains(ordinal), sets[ordinal].completedAt != nil { return sets[ordinal] }
        return nil
    }
    var body: some View {
        if let set, let item {
            let columns = SetTableColumns(item: item)
            SwipeToDelete(action: removeSet) {
            VStack(alignment: .leading, spacing: 3) {
                let stacked = typeSize.isAccessibilitySize || (item.mode == .cardio && (set.weight != nil || set.reps != nil))
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    VStack(spacing: 0) {
                        SetTypeButton(plan: set.plan, change: { plan in
                            store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }
                        }, details: { holdExpanded(); editingDetails = true }) {
                            SetBadge(text: setLabel(set, item: item), plan: set.plan)
                        }.accessibilityLabel("\(palette.title(set.plan)), set \(setLabel(set, item: item)), change set type")
                        if set.plan.load == .percent {
                            Button("\(number(set.plan.percent))%") { open(.percent) }
                                .font(.caption).frame(minWidth: 44, minHeight: 44)
                                .modifier(WeightSettingsInteraction(enabled: true) { holdExpanded(); editingLoad = true })
                        }
                    }.frame(width: typeSize.isAccessibilitySize ? nil : 44)
                    let measurements = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                    measurements {
                        if stacked, let previous {
                            Button("Copy previous: \(loggedSetSummary(previous, unit: store.data.settings.unit))") { copy(previous) }.font(.footnote).buttonStyle(.plain)
                        }
                        if !stacked {
                            if let previous {
                                Button { copy(previous) } label: { Text(previousValue(previous)).font(.footnote).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(width: 64, height: 44) }.buttonStyle(.plain).accessibilityLabel("Copy previous: \(loggedSetSummary(previous, unit: store.data.settings.unit))")
                            } else { Text("–").foregroundStyle(.tertiary).frame(width: 64, height: 44) }
                        }
                        if columns.weight { cell(title: store.data.settings.unit.rawValue.uppercased(), value: set.weight.map { number(store.data.settings.unit.display($0)) }, field: .weight, labeled: stacked) }
                        if columns.reps { cell(title: set.plan.amrap ? "AMRAP" : "REPS", value: set.reps.map(String.init), field: .reps, labeled: stacked, placeholder: set.plan.repRange != nil ? set.plan.repTarget?.replacingOccurrences(of: "-", with: "–") : nil) }
                        if columns.time { cell(title: "TIME", value: set.seconds.map(clockText), field: .time, labeled: stacked) }
                        if columns.distance { cell(title: "METERS", value: set.meters.map { number($0) }, field: .distance, labeled: stacked) }
                        cell(title: "RPE", value: set.rpe.map { number($0) }, field: .rpe, labeled: stacked).frame(maxWidth: stacked || !columns.hasMeasurements ? .infinity : 44)
                        Button { withAnimation(.snappy(duration: 0.2)) { store.toggle(exerciseID, setID) } } label: {
                            let done = set.completedAt != nil
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(done ? palette.on(.completed) : Color.secondary.opacity(0.5))
                                .frame(width: 32, height: 32)
                                .background(done ? palette.completed : palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(set.completedAt == nil ? "Complete" : "Undo") \(palette.title(set.plan).lowercased()) set \(setLabel(set, item: item))").accessibilityIdentifier("workout.\(exerciseID).\(setID).complete")
                    }
                }
                if let rest = set.plan.restSeconds { Label(rest == 0 ? "No rest" : "\(clockText(Double(rest))) rest", systemImage: "timer").font(.caption2).foregroundStyle(palette.rest).padding(.leading, 40).padding(.bottom, 2) }
            }.padding(.horizontal, 2)
            .background(set.completedAt != nil ? palette.wash(.completed) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .accessibilityAction(named: "Set Details") { holdExpanded(); editingDetails = true }
            .accessibilityAction(named: "Log Time") { open(.time) }
            .accessibilityAction(named: "Log Distance") { open(.distance) }
            .accessibilityAction(named: "Rest After Set") { open(.rest) }
            .sheet(item: $edit) { NumberEditor(edit: $0) }
            .sheet(isPresented: $editingLoad) {
                LoadRuleEditor(plan: set.plan, unit: store.data.settings.unit, suggestedWeight: set.weight) { plan in
                    store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }
                }
            }
            .sheet(isPresented: $editingDetails) { LivePlanEditor(exerciseID: exerciseID, setID: setID, initial: set.plan).sheetSize() }
            .sheet(isPresented: $editingReps) {
                RepTargetEditor(plan: set.plan) { plan in
                    store.perform { data in try data.setRepTarget(plan, exerciseID: exerciseID, setID: setID) }
                }
            }
        }
    }
    func cell(title: String, value: String?, field: Field, labeled: Bool = false, placeholder: String? = nil) -> some View {
        Button { open(field) } label: {
            VStack(spacing: 3) {
                if labeled { Text(title).font(.caption2).foregroundStyle(.secondary) }
                Text(value ?? placeholder ?? "–").font(labeled ? .title3.monospacedDigit() : .figure(17)).foregroundStyle(value == nil || (field == .weight && self.set?.weightIsEdited != true && self.set?.completedAt == nil) ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, minHeight: 44).background(self.set?.completedAt == nil ? palette.field : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
        .modifier(RepTargetInteraction(enabled: field == .reps) { holdExpanded(); editingReps = true })
        .modifier(WeightSettingsInteraction(enabled: field == .weight) { holdExpanded(); editingLoad = true })
        .accessibilityLabel("Set \(index + 1), \(title), \(value ?? "not set")\(placeholder.map { ", target \($0)" } ?? "")").accessibilityIdentifier("workout.\(exerciseID).\(setID).\(field.rawValue)")
    }
    func previousValue(_ set: LoggedSet) -> String {
        if let weight = set.weight, let reps = set.reps { return "\(number(store.data.settings.unit.display(weight))) × \(reps)" }
        if let range = set.plan.repRange { return set.weight.map { "\(number(store.data.settings.unit.display($0))) × \(range.lowerBound)-\(range.upperBound)" } ?? "\(range.lowerBound)-\(range.upperBound)" }
        if let seconds = set.seconds { return clockText(seconds) }
        if let reps = set.reps { return "\(reps) reps" }
        if let rpe = set.rpe { return "RPE \(number(rpe))" }
        if let weight = set.weight { return "\(number(store.data.settings.unit.display(weight)))" }
        return "·"
    }
    func copy(_ previous: LoggedSet) {
        holdExpanded()
        store.perform { data in
            try data.setLoggedWeight(previous.weight, exerciseID: exerciseID, setID: setID)
            guard let e = data.activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }), let s = data.activeSession?.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            data.activeSession!.exercises[e].sets[s].reps = previous.reps
            data.activeSession!.exercises[e].sets[s].seconds = previous.seconds
            data.activeSession!.exercises[e].sets[s].meters = previous.meters
            data.activeSession!.exercises[e].sets[s].rpe = previous.rpe
        }
    }
    enum Field: String { case weight, reps, time, distance, rpe, rest, percent }
    func removeSet() { store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } }
    func holdExpanded() {
        if item?.sets.allSatisfy({ $0.completedAt != nil }) == true { store.perform { $0.setExerciseExpanded(exerciseID, expanded: true) } }
    }
    func open(_ field: Field) {
        holdExpanded()
        edit = numericEdit(for: setID, field: field)
    }
    private func numericEdit(for id: UUID, field: Field) -> NumericEdit? {
        guard let item, let index = item.sets.firstIndex(where: { $0.id == id }) else { return nil }
        let set = item.sets[index]
        let unit = store.data.settings.unit
        let value: Double?, title: String, step: Double, maximum: Double
        switch field {
        case .percent: value = set.plan.percent; title = "Percent of working set"; step = 5; maximum = 1000
        case .weight: value = set.weight.map(unit.display); title = "Weight (\(unit.rawValue))"; step = 2.5; maximum = 100000
        case .reps: value = set.reps.map(Double.init); title = "Reps completed"; step = 1; maximum = 10000
        case .time: value = set.seconds.map { $0 / 60 }; title = "Time (minutes)"; step = 1; maximum = 100000
        case .distance: value = set.meters; title = "Distance (meters)"; step = 100; maximum = 10000000
        case .rpe: value = set.rpe; title = "RPE"; step = 0.5; maximum = 10
        case .rest: value = set.plan.restSeconds.map(Double.init); title = "Rest (seconds)"; step = 5; maximum = 86400
        }
        return NumericEdit(title: title, context: "\(item.name), set \(setBadge(item.sets.map(\.plan), index: index, types: store.data.customSetTypes))", value: value, step: step, maximum: maximum, integer: field == .reps || field == .rest,
            previous: adjacentID(id, offset: -1, field: field) != nil ? { adjacent(id, offset: -1, field: field) } : nil,
            next: adjacentID(id, offset: 1, field: field) != nil ? { adjacent(id, offset: 1, field: field) } : nil
        ) { newValue in
            store.perform { data in
                if field == .weight {
                    try data.setLoggedWeight(newValue.map(unit.kilograms), exerciseID: exerciseID, setID: id)
                } else if field == .percent {
                    guard var plan = data.activeSession?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == id })?.plan else { throw TrainingError.invalid("Set unavailable.") }
                    plan.percent = newValue ?? 0
                    try data.replaceSetPlan(exerciseID: exerciseID, setID: id, plan: plan)
                } else {
                    guard let e = data.activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
                          let s = data.activeSession?.exercises[e].sets.firstIndex(where: { $0.id == id }) else { throw TrainingError.invalid("Set unavailable.") }
                    switch field {
                    case .weight, .percent: break
                    case .reps: data.activeSession!.exercises[e].sets[s].reps = newValue.map(Int.init)
                    case .time: data.activeSession!.exercises[e].sets[s].seconds = newValue.map { $0 * 60 }
                    case .distance: data.activeSession!.exercises[e].sets[s].meters = newValue
                    case .rpe: data.activeSession!.exercises[e].sets[s].rpe = newValue
                    case .rest: data.activeSession!.exercises[e].sets[s].plan.restSeconds = newValue.map(Int.init)
                    }
                }
            }
        }
    }
    private func adjacent(_ id: UUID, offset: Int, field: Field) -> NumericEdit? {
        guard let next = adjacentID(id, offset: offset, field: field) else { return nil }
        return numericEdit(for: next, field: field)
    }
    private func adjacentID(_ id: UUID, offset: Int, field: Field) -> UUID? {
        let ids = (item?.sets ?? []).filter { field != .percent || $0.plan.load == .percent }.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    func setLabel(_ set: LoggedSet, item: SessionExercise) -> String { setBadge(item.sets.map(\.plan), index: index, types: store.data.customSetTypes) }
}

/// Short set label used in workout and prescription tables: W1, 1, D1, A, M1, F.
func setBadge(_ plans: [SetPlan], index: Int, types: [CustomSetType]) -> String {
    guard plans.indices.contains(index) else { return "" }
    if let id = plans[index].customTypeID, let type = types.first(where: { $0.id == id }) {
        let count = plans.prefix(index + 1).filter { $0.customTypeID == id }.count
        return type.badge.count >= 3 || plans.filter({ $0.customTypeID == id }).count == 1 ? type.badge : "\(type.badge)\(count)"
    }
    let kinds = plans.map(\.kind)
    let prefix = kinds.prefix(index + 1)
    switch kinds[index] {
    case .warmup: return "W\(prefix.filter { $0 == .warmup }.count)"
    case .drop: return "D\(prefix.filter { $0 == .drop }.count)"
    case .myoActivation: return "A"
    case .failure: return "F"
    case .myoMini: return "M\(prefix.reversed().prefix { $0 == .myoMini }.count)"
    case .working: return "\(prefix.filter { $0 == .working }.count)"
    }
}

func loggedSetSummary(_ set: LoggedSet, unit: WeightUnit) -> String {
    var parts: [String] = []
    if let w = set.weight { parts.append("\(number(unit.display(w))) \(unit.rawValue)") }
    if let reps = set.reps { parts.append("\(reps) reps") }
    else if let range = set.plan.repRange { parts.append("\(range.lowerBound)-\(range.upperBound) reps") }
    if let seconds = set.seconds { parts.append(clockText(seconds)) }
    if let meters = set.meters { parts.append("\(number(meters)) m") }
    if let rpe = set.rpe { parts.append("RPE \(number(rpe))") }
    return parts.joined(separator: " · ")
}

struct SetTableColumns {
    let weight: Bool
    let reps: Bool
    let time: Bool
    let distance: Bool
    var hasMeasurements: Bool { weight || reps || time || distance }
    init(item: SessionExercise) {
        let sets = item.sets
        weight = sets.contains { $0.weight != nil || $0.plan.load != .none }
        reps = sets.contains { $0.reps != nil || $0.plan.reps != nil }
        time = item.mode == .cardio || sets.contains { $0.seconds != nil }
        distance = item.mode == .cardio || sets.contains { $0.meters != nil }
    }
}
