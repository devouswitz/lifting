import SwiftUI
import LiftingCore

struct LiveSetRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) var palette
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    let setID: UUID
    let index: Int
    let present: (ExerciseSheet) -> Void
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
            let unit = store.data.settings.unit
            SwipeToDelete(action: removeSet) {
            VStack(alignment: .leading, spacing: 3) {
                let stacked = typeSize.isAccessibilitySize || (item.mode == .cardio && (set.weight != nil || set.reps != nil))
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    VStack(spacing: 0) {
                        SetTypeButton(plan: set.plan, change: { plan in
                            store.perform { try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }
                        }, convert: { technique in
                            store.perform { try $0.convertSessionSet(exerciseID: exerciseID, setID: setID, to: technique) }
                        }, details: { present(.details(setID)) }) {
                            SetBadge(text: setLabel(item), plan: set.plan)
                        }.accessibilityLabel("\(palette.title(set.plan)), set \(setLabel(item)), change set type")
                        if set.plan.load == .percent {
                            Button("\(number(set.plan.percent))%") { open(.percent) }
                                .font(.caption).frame(minWidth: 44, minHeight: 20)
                                .longPress("Weight settings") { present(.load(setID)) }
                        }
                    }.frame(width: typeSize.isAccessibilitySize ? nil : 44)
                    let measurements = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                    measurements {
                        if let previous {
                            let summary = loggedSetSummary(previous, mode: item.mode, unit: unit)
                            if stacked { Button("Copy previous: \(summary)") { copy(previous) }.font(.footnote).buttonStyle(.plain) }
                            else {
                                Button { copy(previous) } label: { Text(previousValue(previous, mode: item.mode)).font(.footnote).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(width: 64, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel("Copy previous: \(summary)")
                            }
                        } else if !stacked { Text("–").foregroundStyle(.tertiary).frame(width: 64, height: 44) }
                        if columns.weight {
                            cell(title: item.mode == .bodyweight ? "+\(unit.rawValue.uppercased())" : unit.rawValue.uppercased(), value: loadText(set.weight, mode: item.mode, unit: unit), field: .weight, labeled: stacked)
                                .longPress("Weight settings") { present(.load(setID)) }
                        }
                        if columns.reps {
                            cell(title: set.plan.amrap ? "AMRAP" : "REPS", value: set.reps.map(String.init), field: .reps, labeled: stacked,
                                 placeholder: set.plan.repRange != nil || set.plan.amrap ? set.plan.repTarget.map(displayTarget) : nil)
                                .longPress("Edit rep target") { present(.reps(setID)) }
                        }
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
                        }.buttonStyle(.plain).accessibilityLabel("\(set.completedAt == nil ? "Complete" : "Undo") \(palette.title(set.plan).lowercased()) set \(setLabel(item))").accessibilityIdentifier("workout.\(exerciseID).\(setID).complete")
                    }
                }
                if let rest = set.plan.restSeconds {
                    Button { open(.rest) } label: { Label(rest == 0 ? "No rest" : "\(clockText(Double(rest))) rest", systemImage: "timer") }
                        .buttonStyle(.plain).font(.caption2).foregroundStyle(palette.rest).padding(.leading, 40).padding(.bottom, 2)
                }
            }.padding(.horizontal, 2)
            .background(set.completedAt != nil ? palette.wash(.completed) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .accessibilityAction(named: "Set Details") { present(.details(setID)) }
            .accessibilityAction(named: "Log Time") { open(.time) }
            .accessibilityAction(named: "Log Distance") { open(.distance) }
            .accessibilityAction(named: "Rest After Set") { open(.rest) }
        }
    }
    func cell(title: String, value: String?, field: SetField, labeled: Bool = false, placeholder: String? = nil) -> some View {
        Button { open(field) } label: {
            VStack(spacing: 3) {
                if labeled { Text(title).font(.caption2).foregroundStyle(.secondary) }
                Text(value ?? placeholder ?? "–").font(labeled ? .title3.monospacedDigit() : .figure(17)).foregroundStyle(value == nil || (field == .weight && self.set?.weightIsEdited != true && self.set?.completedAt == nil) ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, minHeight: 44).background(self.set?.completedAt == nil ? palette.field : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
        .accessibilityLabel("Set \(index + 1), \(title), \(value ?? "not set")\(placeholder.map { ", target \($0)" } ?? "")").accessibilityIdentifier("workout.\(exerciseID).\(setID).\(field.rawValue)")
    }
    func previousValue(_ set: LoggedSet, mode: ExerciseMode) -> String {
        let unit = store.data.settings.unit
        let load = loadText(set.weight, mode: mode, unit: unit)
        if let reps = set.reps { return load.map { "\($0) × \(reps)" } ?? "\(reps) reps" }
        if let range = set.plan.repRange { return load.map { "\($0) × \(range.lowerBound)-\(range.upperBound)" } ?? "\(range.lowerBound)-\(range.upperBound)" }
        if let seconds = set.seconds { return clockText(seconds) }
        if let rpe = set.rpe { return "RPE \(number(rpe))" }
        return load ?? "·"
    }
    func copy(_ previous: LoggedSet) {
        store.perform { data in
            try data.setLoggedWeight(previous.weight, exerciseID: exerciseID, setID: setID)
            guard let e = data.activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }), let s = data.activeSession?.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            data.activeSession!.exercises[e].sets[s].reps = previous.reps
            data.activeSession!.exercises[e].sets[s].seconds = previous.seconds
            data.activeSession!.exercises[e].sets[s].meters = previous.meters
            data.activeSession!.exercises[e].sets[s].rpe = previous.rpe
        }
    }
    func removeSet() { store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } }
    func open(_ field: SetField) {
        if let edit = numericEdit(for: setID, field: field) { present(.keypad(edit)) }
    }
    private func numericEdit(for id: UUID, field: SetField) -> NumericEdit? {
        guard let item, let index = item.sets.firstIndex(where: { $0.id == id }) else { return nil }
        let set = item.sets[index]
        let unit = store.data.settings.unit
        let value: Double?
        switch field {
        case .percent: value = set.plan.percent
        case .weight: value = set.weight.map(unit.display)
        case .reps: value = set.reps.map(Double.init)
        case .time: value = set.seconds
        case .distance: value = set.meters
        case .rpe: value = set.rpe
        case .rest: value = set.plan.restSeconds.map(Double.init)
        }
        return field.edit(value: value, context: "\(item.name), set \(setBadge(item.sets.map(\.plan), index: index, types: store.data.customSetTypes))", unit: unit, mode: item.mode,
            previous: adjacentID(id, offset: -1, field: field) != nil ? { adjacent(id, offset: -1, field: field) } : nil,
            next: adjacentID(id, offset: 1, field: field) != nil ? { adjacent(id, offset: 1, field: field) } : nil,
            // Confirming a rep count logs the set.
            confirm: field == .reps ? { store.completeIfLogged(exerciseID, id) } : nil
        ) { newValue in
            store.perform { data in
                switch field {
                case .weight: try data.setLoggedWeight(newValue.map(unit.kilograms), exerciseID: exerciseID, setID: id)
                case .percent:
                    guard var plan = data.activeSession?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == id })?.plan else { throw TrainingError.invalid("Set unavailable.") }
                    plan.percent = newValue ?? 0
                    try data.replaceSetPlan(exerciseID: exerciseID, setID: id, plan: plan)
                default:
                    guard let e = data.activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
                          let s = data.activeSession?.exercises[e].sets.firstIndex(where: { $0.id == id }) else { throw TrainingError.invalid("Set unavailable.") }
                    switch field {
                    case .reps: data.activeSession!.exercises[e].sets[s].reps = newValue.map(Int.init)
                    case .time: data.activeSession!.exercises[e].sets[s].seconds = newValue
                    case .distance: data.activeSession!.exercises[e].sets[s].meters = newValue
                    case .rpe: data.activeSession!.exercises[e].sets[s].rpe = newValue
                    case .rest: data.activeSession!.exercises[e].sets[s].plan.restSeconds = newValue.map(Int.init)
                    case .weight, .percent: break
                    }
                }
            }
        }
    }
    private func adjacent(_ id: UUID, offset: Int, field: SetField) -> NumericEdit? {
        adjacentID(id, offset: offset, field: field).flatMap { numericEdit(for: $0, field: field) }
    }
    private func adjacentID(_ id: UUID, offset: Int, field: SetField) -> UUID? {
        let ids = (item?.sets ?? []).filter { field != .percent || $0.plan.load == .percent }.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    func setLabel(_ item: SessionExercise) -> String { setBadge(item.sets.map(\.plan), index: index, types: store.data.customSetTypes) }
}

/// A value in a set row. Workouts and saved days share each field's keypad.
enum SetField: String {
    case weight, reps, time, distance, rpe, rest, percent

    func edit(value: Double?, context: String, unit: WeightUnit, mode: ExerciseMode, previous: (() -> NumericEdit?)?, next: (() -> NumericEdit?)?,
              confirm: (() -> Void)? = nil, save: @escaping (Double?) -> Bool) -> NumericEdit {
        let title: String, step: Double, maximum: Double
        var format = NumericEdit.Format.number
        switch self {
        case .weight:
            title = mode == .bodyweight ? "Added Weight (\(unit.rawValue))" : "Weight (\(unit.rawValue))"; step = 2.5; maximum = 100000
            if mode == .bodyweight { format = .signed }
        case .reps: title = "Reps"; step = 1; maximum = 10000
        case .time: title = "Time"; step = 60; maximum = 359999; format = .duration
        case .distance: title = "Distance (meters)"; step = 100; maximum = 10000000
        case .rpe: title = "RPE"; step = 0.5; maximum = 10
        case .rest: title = "Rest After Set"; step = 15; maximum = 86400; format = .duration
        case .percent: title = "Percent of Working Set"; step = 5; maximum = 1000
        }
        return NumericEdit(title: title, context: context, value: value, step: step, maximum: maximum, integer: self == .reps, format: format,
                           presets: self == .rest ? restPresets : [], previous: previous, next: next, confirm: confirm, onSave: save)
    }
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

func loggedSetSummary(_ set: LoggedSet, mode: ExerciseMode = .strength, unit: WeightUnit) -> String {
    var parts: [String] = []
    if let load = loadText(set.weight, mode: mode, unit: unit) { parts.append(mode == .bodyweight && load == "BW" ? load : "\(load) \(unit.rawValue)") }
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
        weight = item.mode == .bodyweight || sets.contains { $0.weight != nil || $0.plan.load != .none }
        reps = sets.contains { $0.reps != nil || $0.plan.reps != nil || $0.plan.amrap }
        time = item.mode == .cardio || sets.contains { $0.seconds != nil }
        distance = item.mode == .cardio || sets.contains { $0.meters != nil }
    }
}
