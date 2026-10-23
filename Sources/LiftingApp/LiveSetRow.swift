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
                    VStack(spacing: 1) {
                        Menu { setMenu(set) } label: { SetBadge(text: setLabel(set, item: item), plan: set.plan) }
                            .compactMenu().accessibilityLabel("\(palette.title(set.plan)), set \(setLabel(set, item: item)), options")
                        if set.plan.load == .percent { Text("\(number(set.plan.percent))%").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary) }
                    }.frame(width: 32, height: 44)
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
                                .frame(width: 40, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(set.completedAt == nil ? "Complete" : "Undo") \(palette.title(set.plan).lowercased()) set \(setLabel(set, item: item))").accessibilityIdentifier("workout.\(exerciseID).\(setID).complete")
                    }
                }
                if let rest = set.plan.restSeconds { Label(rest == 0 ? "No rest" : "\(clockText(Double(rest))) rest", systemImage: "timer").font(.caption2).foregroundStyle(palette.rest).padding(.leading, 40).padding(.bottom, 2) }
            }.padding(.horizontal, 2)
            .background(set.completedAt != nil ? palette.wash(.completed) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .contextMenu {
                Button("Set Details", systemImage: "slider.horizontal.3") { holdExpanded(); editingDetails = true }
                if !columns.time { Button("Log Time", systemImage: "stopwatch") { open(.time) } }
                if !columns.distance { Button("Log Distance", systemImage: "ruler") { open(.distance) } }
                setMenu(set)
            }
            .sheet(item: $edit) { NumericPad(edit: $0) }
            .sheet(isPresented: $editingDetails) { LivePlanEditor(exerciseID: exerciseID, setID: setID, initial: set.plan).sheetSize() }
            .sheet(isPresented: $editingReps) {
                RepTargetEditor(plan: set.plan) { plan in
                    store.perform { data in try data.setRepTarget(plan, exerciseID: exerciseID, setID: setID) }
                }
            }
        }
    }
    @ViewBuilder func setMenu(_ set: LoggedSet) -> some View {
        Button("Rest After Set", systemImage: "timer") { open(.rest) }
        Menu("Set Type") {
            ForEach(SetKind.allCases) { kind in
                Button { store.editSet(exerciseID, setID) { $0.plan.kind = kind; $0.plan.customTypeID = nil } } label: {
                    if set.plan.kind == kind && set.plan.customTypeID == nil { Label(kind.title, systemImage: "checkmark") } else { Text(kind.title) }
                }
            }
            if !store.data.customSetTypes.isEmpty {
                Divider()
                ForEach(store.data.customSetTypes) { type in
                    Button { store.editSet(exerciseID, setID) { $0.plan.kind = type.countsAs; $0.plan.customTypeID = type.id } } label: {
                        if set.plan.customTypeID == type.id { Label(type.name, systemImage: "checkmark") } else { Text(type.name) }
                    }
                }
            }
        }
        Divider()
        Button("Delete Set", systemImage: "trash", role: .destructive, action: removeSet)
    }
    func cell(title: String, value: String?, field: Field, labeled: Bool = false, placeholder: String? = nil) -> some View {
        Button { open(field) } label: {
            VStack(spacing: 3) {
                if labeled { Text(title).font(.caption2).foregroundStyle(.secondary) }
                Text(value ?? placeholder ?? "–").font(.figure(17)).foregroundStyle(value == nil || (field == .weight && self.set?.weightIsEdited != true && self.set?.completedAt == nil) ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, minHeight: 36).background(self.set?.completedAt == nil ? palette.field : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain)
        .modifier(RepTargetInteraction(enabled: field == .reps) { holdExpanded(); editingReps = true })
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
    enum Field: String { case weight, reps, time, distance, rpe, rest }
    func removeSet() { store.editExercise(exerciseID) { $0.sets.removeAll { $0.id == setID } } }
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
        edit = NumericEdit(title: title, context: item.map { "\($0.name), set \(setLabel(set, item: $0))" }, value: value, step: step, maximum: maximum, integer: field == .reps || field == .rest) { newValue in
            if field == .weight {
                store.perform { try $0.setLoggedWeight(newValue.map(unit.kilograms), exerciseID: exerciseID, setID: setID) }
                return
            }
            store.editSet(exerciseID, setID) { s in
                switch field { case .weight: break; case .reps: s.reps = newValue.map(Int.init); case .time: s.seconds = newValue.map { $0 * 60 }; case .distance: s.meters = newValue; case .rpe: s.rpe = newValue; case .rest: s.plan.restSeconds = newValue.map(Int.init) }
            }
        }
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

struct NumericEdit: Identifiable {
    let id = UUID()
    let title: String
    var context: String? = nil
    let value: Double?
    let step: Double
    let maximum: Double
    let integer: Bool
    let onSave: (Double?) -> Void
}

/// Compact keypad sheet for entering one value without leaving the workout.
struct NumericPad: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.palette) var palette
    @Environment(\.dynamicTypeSize) var typeSize
    let edit: NumericEdit
    @FocusState private var keysFocused: Bool
    @State private var text: String
    @State private var error: String?
    @State private var replacing = true
    init(edit: NumericEdit) { self.edit = edit; _text = State(initialValue: edit.value.map { number($0, decimals: 3) } ?? "") }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(palette.action)
                Spacer()
                VStack(spacing: 1) {
                    Text(edit.title).font(.headline)
                    if let context = edit.context { Text(context).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Clear") { text = ""; replacing = false }.foregroundStyle(palette.action)
            }
            Text(text.isEmpty ? "–" : text).font(.figure(44, weight: .bold)).foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 56).accessibilityIdentifier("number.value").accessibilityLabel("\(edit.title), \(text.isEmpty ? "empty" : text)")
            HStack(spacing: 8) {
                ForEach([-2.0, -1, 1, 2], id: \.self) { multiplier in
                    Button { text = number(min(edit.maximum, max(0, (Double(text) ?? 0) + edit.step * multiplier)), decimals: 3); replacing = false } label: {
                        Text("\(multiplier > 0 ? "+" : "−")\(number(edit.step * abs(multiplier)))").font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.action).frame(maxWidth: .infinity, minHeight: 34).background(palette.wash(.action), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                    Button { press(key) } label: {
                        Group { if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) } }
                            .font(.title2.weight(.medium)).foregroundStyle(key == "." && edit.integer ? Color.secondary.opacity(0.3) : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 50).background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain).disabled(key == "." && edit.integer).accessibilityLabel(key == "⌫" ? "Delete" : key)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(palette.failure) }
            Button(action: save) { Text("Done").frame(maxWidth: .infinity) }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("number.done")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
        .frame(idealWidth: 420)
        // Hardware keyboards (iPad, Mac) type into the pad directly.
        .focusable().focused($keysFocused).focusEffectDisabled()
        .onAppear { keysFocused = true }
        .onKeyPress { key in
            if key.key == .return { save(); return .handled }
            if key.key == .delete { press("⌫"); return .handled }
            if key.key == .escape { dismiss(); return .handled }
            let character = key.characters == "," ? "." : key.characters
            if character.count == 1, "0123456789.".contains(character) { press(character); return .handled }
            return .ignored
        }
        .presentationBackground(palette.card)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(edit.context == nil ? 520 : 540), .large])
        .presentationDragIndicator(.visible)
    }
    /// The first key replaces the shown value, so typing a new weight does not append to the old one.
    private func press(_ key: String) {
        error = nil
        if replacing && key != "⌫" { text = ""; replacing = false }
        switch key {
        case "⌫": replacing = false; if !text.isEmpty { text.removeLast() }
        case ".": if !edit.integer && !text.contains(".") { text += text.isEmpty ? "0." : "." }
        default: if text.count < 10 { text = text == "0" ? key : text + key }
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
