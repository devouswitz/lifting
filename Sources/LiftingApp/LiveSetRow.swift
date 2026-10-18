import SwiftUI
import LiftingCore

struct LiveSetRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.dynamicTypeSize) var typeSize
    let exerciseID: UUID
    let setID: UUID
    let index: Int
    @State private var edit: NumericEdit?
    @State private var editingPlan = false
    var item: SessionExercise? { store.data.activeSession?.exercises.first { $0.id == exerciseID } }
    var set: LoggedSet? { item?.sets.first { $0.id == setID } }
    var previous: LoggedSet? {
        guard let item, let set else { return nil }
        let sets = (store.data.sessions.sorted { $0.startedAt > $1.startedAt }.compactMap { $0.exercises.first { $0.variantID == item.variantID } }.first?.sets ?? []).filter { $0.plan.kind == set.plan.kind }
        let ordinal = item.sets.prefix(index).filter { $0.plan.kind == set.plan.kind }.count
        if sets.indices.contains(ordinal), sets[ordinal].completedAt != nil { return sets[ordinal] }
        return nil
    }
    var body: some View {
        if let set, let item {
            let columns = SetTableColumns(item: item, warmup: set.plan.kind == .warmup)
            VStack(alignment: .leading, spacing: 3) {
                let stacked = typeSize.isAccessibilitySize || (item.mode == .cardio && (set.weight != nil || set.reps != nil))
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    VStack(spacing: 0) {
                    Menu {
                        Button(set.plan.kind == .warmup ? "Edit Warm-up Targets" : "Edit Set Targets") { holdExpanded(); editingPlan = true }
                        Button("Log reps") { open(.reps) }
                        Divider()
                        ForEach(SetKind.allCases) { kind in Button(kind.title) { store.editSet(exerciseID, setID) { $0.plan.kind = kind } } }
                        Button("Delete set", role: .destructive) { store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } }
                    } label: {
                        Text(setLabel(set, item: item)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 28, height: set.plan.load == .percent ? 30 : 44)
                    }.compactMenu().accessibilityLabel("\(set.plan.kind.title), set \(index + 1), options")
                    if set.plan.load == .percent { Text("\(number(set.plan.percent))%").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }.frame(width: 28)
                    HStack(spacing: 6) {
                        if !stacked {
                            if let previous {
                                Button { copy(previous) } label: { Text(previousValue(previous)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, height: 44) }.buttonStyle(.plain).accessibilityLabel("Copy previous: \(loggedSetSummary(previous, unit: store.data.settings.unit))")
                            } else { Text("·").foregroundStyle(.tertiary).frame(width: 64, height: 44) }
                        }
                        if columns.weight { cell(title: store.data.settings.unit.rawValue.uppercased(), value: set.weight.map { number(store.data.settings.unit.display($0)) }, field: .weight, labeled: stacked) }
                        if columns.reps { cell(title: set.plan.amrap ? "AMRAP" : "REPS", value: set.reps.map(String.init), field: .reps, labeled: stacked, placeholder: set.plan.repRange != nil ? set.plan.repTarget : nil) }
                        if columns.time { cell(title: "TIME", value: set.seconds.map(clockText), field: .time, labeled: stacked) }
                        if columns.distance { cell(title: "METERS", value: set.meters.map { number($0) }, field: .distance, labeled: stacked) }
                        cell(title: "RPE", value: set.rpe.map { number($0) }, field: .rpe, labeled: stacked).frame(maxWidth: stacked || !columns.hasMeasurements ? .infinity : 42)
                        Button { store.toggle(exerciseID, setID) } label: {
                            Image(systemName: set.completedAt == nil ? "square" : "checkmark.square.fill").font(.system(size: 23)).foregroundStyle(set.completedAt == nil ? Color.secondary.opacity(0.6) : Palette.tint(scheme)).frame(width: 40, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(set.completedAt == nil ? "Complete set \(index + 1)" : "Undo set \(index + 1)").accessibilityIdentifier("workout.\(exerciseID).\(setID).complete")
                    }
                }
                if let rest = set.plan.restSeconds { Text("\(rest)s rest").font(.caption2).foregroundStyle(.secondary).padding(.leading, 34) }
            }.padding(.horizontal, 2).padding(.vertical, 2)
            .background(set.completedAt != nil ? Palette.tint(scheme).opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                Button("Edit Set Targets") { holdExpanded(); editingPlan = true }
                Button("Add time") { open(.time) }; Button("Add distance") { open(.distance) }
                Button("Edit rest") { open(.rest) }
                Button("Delete set", role: .destructive) { store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } }
            }
            .sheet(item: $edit) { NumericPad(edit: $0).sheetSize() }
            .sheet(isPresented: $editingPlan) { LivePlanEditor(exerciseID: exerciseID, setID: setID, initial: set.plan).environmentObject(store).sheetSize() }
        }
    }
    func cell(title: String, value: String?, field: Field, labeled: Bool = false, placeholder: String? = nil) -> some View {
        Button { open(field) } label: {
            VStack(spacing: 3) {
                if labeled { Text(title).font(.caption2).foregroundStyle(.secondary) }
                Text(value ?? placeholder ?? "·").font(.body.weight(.medium)).monospacedDigit().foregroundStyle(value == nil ? .secondary : .primary)
            }.frame(maxWidth: .infinity, minHeight: 38).background(Palette.secondary(scheme).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel("Set \(index + 1), \(title), \(value ?? "not set")\(placeholder.map { ", target \($0)" } ?? "")").accessibilityIdentifier("workout.\(exerciseID).\(setID).\(field.rawValue)")
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
        store.editSet(exerciseID, setID) { s in s.weight = previous.weight; s.reps = previous.reps; s.seconds = previous.seconds; s.meters = previous.meters; s.rpe = previous.rpe }
    }
    enum Field: String { case weight, reps, time, distance, rpe, rest }
    func holdExpanded() {
        if item?.sets.allSatisfy({ $0.completedAt != nil }) == true { store.perform { $0.setExerciseExpanded(exerciseID, expanded: true) } }
    }
    func open(_ field: Field) {
        guard let set else { return }
        holdExpanded()
        let unit = store.data.settings.unit
        let value: Double?, title: String, step: Double, maximum: Double
        switch field {
        case .weight: value = set.weight.map(unit.display); title = "Weight (\(unit.rawValue))"; step = 2.5; maximum = 100000
        case .reps: value = set.reps.map(Double.init); title = "Reps completed"; step = 1; maximum = 10000
        case .time: value = set.seconds.map { $0 / 60 }; title = "Time (minutes)"; step = 1; maximum = 100000
        case .distance: value = set.meters; title = "Distance (meters)"; step = 100; maximum = 10000000
        case .rpe: value = set.rpe; title = "RPE"; step = 0.5; maximum = 10
        case .rest: value = set.plan.restSeconds.map(Double.init); title = "Rest (seconds)"; step = 5; maximum = 86400
        }
        edit = NumericEdit(title: title, value: value, step: step, maximum: maximum, integer: field == .reps || field == .rest) { newValue in
            store.editSet(exerciseID, setID) { s in
                switch field { case .weight: s.weight = newValue.map(unit.kilograms); case .reps: s.reps = newValue.map(Int.init); case .time: s.seconds = newValue.map { $0 * 60 }; case .distance: s.meters = newValue; case .rpe: s.rpe = newValue; case .rest: s.plan.restSeconds = newValue.map(Int.init) }
            }
        }
    }
    func setLabel(_ set: LoggedSet, item: SessionExercise) -> String {
        switch set.plan.kind {
        case .warmup: return "W\(item.sets.prefix(index + 1).filter { $0.plan.kind == .warmup }.count)"
        case .drop: return "D\(item.sets.prefix(index + 1).filter { $0.plan.kind == .drop }.count)"
        case .myoActivation: return "A"
        case .myoMini: return "M\(item.sets.prefix(index + 1).reversed().prefix { $0.plan.kind == .myoMini }.count)"
        case .working: return "\(item.sets.prefix(index + 1).filter { $0.plan.kind == .working }.count)"
        }
    }
}

struct NumericEdit: Identifiable {
    let id = UUID()
    let title: String
    let value: Double?
    let step: Double
    let maximum: Double
    let integer: Bool
    let onSave: (Double?) -> Void
}

struct NumericPad: View {
    @Environment(\.dismiss) var dismiss
    let edit: NumericEdit
    @State private var text: String
    @State private var error: String?
    init(edit: NumericEdit) { self.edit = edit; _text = State(initialValue: edit.value.map { number($0, decimals: 3) } ?? "") }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Optional", text: $text).font(.system(.largeTitle, design: .rounded).weight(.semibold)).multilineTextAlignment(.center).textFieldStyle(.plain).monospacedDigit().padding(.vertical, 12).accessibilityIdentifier("number.value")
                HStack(spacing: 12) {
                    ForEach([-2.0, -1, 1, 2], id: \.self) { multiplier in
                        Button("\(multiplier > 0 ? "+" : "")\(number(edit.step * multiplier))") { text = number(min(edit.maximum, max(0, (Double(text) ?? 0) + edit.step * multiplier)), decimals: 3) }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { digit in
                        Button { if digit == "⌫" { if !text.isEmpty { text.removeLast() } } else if digit == "." { if !edit.integer && !text.contains(".") { text += text.isEmpty ? "0." : "." } } else if text.count < 10 { text = text == "0" ? digit : text + digit } } label: { Text(digit).font(.title2.weight(.medium)).frame(maxWidth: .infinity, minHeight: 55) }.buttonStyle(.bordered)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                HStack { Button("Clear") { text = "" }; Spacer(); Button("Done", action: save).buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("number.done") }
                Spacer(minLength: 0)
            }.padding(24).navigationTitle(edit.title).inlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    func save() {
        if text.isEmpty { edit.onSave(nil); dismiss(); return }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0, value <= edit.maximum, !edit.integer || value.rounded() == value else { error = "Enter a value from 0 to \(number(edit.maximum))."; return }
        edit.onSave(value); dismiss()
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

struct LivePlanEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let exerciseID: UUID
    let setID: UUID
    @State var plan: SetPlan
    init(exerciseID: UUID, setID: UUID, initial: SetPlan) { self.exerciseID = exerciseID; self.setID = setID; _plan = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            PlanEditor(plan: $plan, unit: store.data.settings.unit)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply Today") { if store.perform({ try $0.replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: plan) }) { dismiss() } } }
                }
        }
    }
}

struct SetTableColumns {
    let weight: Bool
    let reps: Bool
    let time: Bool
    let distance: Bool
    var hasMeasurements: Bool { weight || reps || time || distance }
    init(item: SessionExercise, warmup: Bool) {
        let sets = item.sets.filter { ($0.plan.kind == .warmup) == warmup }
        weight = sets.contains { $0.weight != nil || $0.plan.load != .none }
        reps = sets.contains { $0.reps != nil || $0.plan.reps != nil }
        time = item.mode == .cardio || sets.contains { $0.seconds != nil }
        distance = item.mode == .cardio || sets.contains { $0.meters != nil }
    }
}
