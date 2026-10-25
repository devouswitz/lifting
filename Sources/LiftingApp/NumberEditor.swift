import SwiftUI
import LiftingCore

struct NumericEdit: Identifiable {
    enum Format { case number, signed, duration }
    let id = UUID()
    let title: String
    var context: String? = nil
    let value: Double?
    let step: Double
    let maximum: Double
    var integer = false
    var format = Format.number
    /// Durations offered as one-tap choices, in seconds.
    var presets: [Double] = []
    var previous: (() -> NumericEdit?)? = nil
    var next: (() -> NumericEdit?)? = nil
    /// Runs after an entry is confirmed: the checkmark, Next Set, or a changed value dismissed by swipe.
    var confirm: (() -> Void)? = nil
    let onSave: (Double?) -> Bool
}

/// Rest durations offered on the rest keypad.
let restPresets: [Double] = [60, 90, 120, 180, 300]

/// The keypad's value: a number, or a duration typed like a microwave timer.
enum KeypadValue: Equatable {
    case number(NumericEntry), duration(DurationEntry)
    enum Key { case digit(String), sign, backspace, clear, adjust(Double), set(Double) }

    init(_ edit: NumericEdit, value: Double?? = nil) {
        let value = value ?? edit.value
        self = edit.format == .duration
            ? .duration(DurationEntry(seconds: value, maximum: edit.maximum))
            : .number(NumericEntry(value: value, maximum: edit.maximum, integer: edit.integer, signed: edit.format == .signed))
    }
    static func integer(_ value: Int?) -> KeypadValue { .number(NumericEntry(value: value.map(Double.init), maximum: 10000, integer: true)) }

    var value: Double? { switch self { case .number(let e): return e.value; case .duration(let e): return e.seconds } }
    var text: String { switch self { case .number(let e): return e.text; case .duration(let e): return e.digits.isEmpty ? "" : e.text } }
    var changed: Bool { switch self { case .number(let e): return e.changed; case .duration(let e): return e.changed } }
    var isValid: Bool { switch self { case .number(let e): return e.isValid; case .duration(let e): return e.isValid } }
    var allowsDecimal: Bool { if case .number(let e) = self { return !e.integer }; return false }
    var allowsSign: Bool { if case .number(let e) = self { return e.signed }; return false }
    var maximum: Double { switch self { case .number(let e): return e.maximum; case .duration(let e): return e.maximum } }

    mutating func press(_ key: Key) {
        switch self {
        case .number(var e):
            switch key {
            case .digit(let d): e.insert(d)
            case .sign: e.toggleSign()
            case .backspace: e.backspace()
            case .clear: e.clear()
            case .adjust(let delta): e.adjust(by: delta)
            case .set(let value): e.clear(); e.adjust(by: value)
            }
            self = .number(e)
        case .duration(var e):
            switch key {
            case .digit(let d): e.insert(d)
            case .sign: break
            case .backspace: e.backspace()
            case .clear: e.clear()
            case .adjust(let delta): e.adjust(by: delta)
            case .set(let value): e.set(value)
            }
            self = .duration(e)
        }
    }
    mutating func select() { if case .number(var e) = self { e.select(); self = .number(e) } }
}

/// A keypad stays open while moving through sets. Only edited values become overrides.
struct NumberEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var edit: NumericEdit
    @State private var entry: KeypadValue
    @State private var resolved = false
    init(edit: NumericEdit) {
        _edit = State(initialValue: edit)
        _entry = State(initialValue: KeypadValue(edit))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let context = edit.context { Text(context).font(.subheadline).foregroundStyle(.secondary) }
                    if edit.previous != nil || edit.next != nil {
                        HStack {
                            Button("Previous Set", systemImage: "chevron.left") { advance(edit.previous, confirming: false) }.disabled(edit.previous == nil)
                            Spacer()
                            Button("Next Set", systemImage: "chevron.right") { advance(edit.next, confirming: true) }.disabled(edit.next == nil)
                        }.font(.subheadline).buttonStyle(.plain).frame(minHeight: 44).disabled(!entry.isValid)
                    }
                    NumericDisplay(entry: $entry, title: edit.title)
                    NumericKeys(entry: $entry, step: edit.step, presets: edit.presets)
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle(edit.title).inlineTitle()
                .toolbar {
                    if !entry.isValid { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { resolved = true; dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { if commit() { edit.confirm?(); resolved = true; dismiss() } }
                            .labelStyle(.iconOnly).disabled(!entry.isValid).keyboardShortcut(.defaultAction)
                    }
                }
        }
        .interactiveDismissDisabled(!entry.isValid)
        .onDisappear {
            guard !resolved else { return }
            let changed = entry.changed
            if commit(), changed { edit.confirm?() }
        }
        .modifier(KeypadPresentation())
    }
    private func commit() -> Bool {
        guard entry.isValid else { return false }
        guard entry.changed else { return true }
        guard edit.onSave(entry.value) else { return false }
        entry = KeypadValue(edit, value: entry.value)
        return true
    }
    private func advance(_ destination: (() -> NumericEdit?)?, confirming: Bool) {
        guard commit() else { return }
        if confirming { edit.confirm?() }
        guard let next = destination?() else { return }
        edit = next
        entry = KeypadValue(next)
    }
}

/// A form row for a duration, entered on the m:ss keypad.
struct DurationRow: View {
    @Environment(\.palette) private var palette
    let title: String
    @Binding var seconds: Double?
    var placeholder = "None"
    var presets: [Double] = []
    var maximum: Double = 86400
    @State private var editing: NumericEdit?
    var body: some View {
        Button {
            editing = NumericEdit(title: title, value: seconds, step: 15, maximum: maximum, format: .duration, presets: presets) { value in seconds = value; return true }
        } label: {
            LabeledContent(title) { Text(seconds.map(clockText) ?? placeholder).monospacedDigit().foregroundStyle(seconds == nil ? Color.secondary : palette.rest) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .sheet(item: $editing) { NumberEditor(edit: $0) }
    }
}

extension DurationRow {
    init(_ title: String, seconds: Binding<Int?>, placeholder: String = "None", presets: [Double] = restPresets) {
        self.init(title: title, seconds: Binding(get: { seconds.wrappedValue.map(Double.init) }, set: { seconds.wrappedValue = $0.map { Int($0) } }), placeholder: placeholder, presets: presets)
    }
    init(_ title: String, seconds: Binding<Int>, presets: [Double] = restPresets) {
        self.init(title: title, seconds: Binding(get: { Double(seconds.wrappedValue) }, set: { seconds.wrappedValue = Int($0 ?? 0) }), placeholder: "0:00", presets: presets)
    }
}

/// A set's rep target on the keypad: No count, Reps, Rep range, or AMRAP with an optional goal.
/// Ranges keep both bounds, and moving between sets commits only a complete target.
struct RepValuesEditor: View {
    @State var plan: SetPlan
    let save: (SetPlan) -> Bool
    var adjacent: ((UUID, Int) -> SetPlan?)? = nil
    @State private var mode: RepTargetMode
    @State private var lower: KeypadValue
    @State private var upper: KeypadValue
    @State private var exact: KeypadValue = .integer(nil)
    /// Which value the keys type into while a range is shown.
    private enum Bound { case lower, upper, exact }
    @State private var bound = Bound.lower
    init(plan: SetPlan, save: @escaping (SetPlan) -> Bool, adjacent: ((UUID, Int) -> SetPlan?)? = nil) {
        _plan = State(initialValue: plan); self.save = save; self.adjacent = adjacent
        _mode = State(initialValue: RepTargetMode(plan))
        _lower = State(initialValue: .integer(plan.reps))
        _upper = State(initialValue: .integer(plan.repCeiling))
    }
    private var edited: SetPlan {
        var target = plan
        target.amrap = mode == .amrap
        // A number typed in Exact replaces the range with that one count.
        if mode == .range, bound == .exact, let value = exact.value { target.reps = Int(value); target.repCeiling = nil; return target }
        switch mode {
        case .none: target.reps = nil; target.repCeiling = nil
        case .exact, .amrap: target.reps = lower.value.map(Int.init); target.repCeiling = nil
        case .range: target.reps = lower.value.map(Int.init); target.repCeiling = upper.value.map(Int.init)
        }
        return target
    }
    private var valid: Bool {
        switch mode {
        case .none: return true
        case .amrap: return lower.isValid
        case .exact: return lower.isValid && lower.value != nil
        case .range: return bound == .exact ? exact.isValid : lower.isValid && upper.isValid && (lower.value.flatMap { l in upper.value.map { $0 >= l } } ?? false)
        }
    }
    var body: some View {
        DraftEditor(valid: valid, changed: !edited.hasSameTarget(as: plan), save: commit) {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Target", selection: $mode) { ForEach(RepTargetMode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("reps.mode")
                        .onChange(of: mode) { _, value in
                            bound = .lower; lower.select()
                            if value == .range, upper.value == nil, let low = lower.value { upper = .integer(Int(low) + 2) }
                        }
                    if let adjacent {
                        HStack {
                            Button("Previous Set", systemImage: "chevron.left") { advance(-1) }.disabled(adjacent(plan.id, -1) == nil)
                            Spacer()
                            Button("Next Set", systemImage: "chevron.right") { advance(1) }.disabled(adjacent(plan.id, 1) == nil)
                        }.font(.subheadline).buttonStyle(.plain).frame(minHeight: 44).disabled(!valid)
                    }
                    switch mode {
                    case .none: EmptyView()
                    case .exact: NumericDisplay(entry: $lower, title: "Target reps")
                    case .amrap: NumericDisplay(entry: $lower, title: "Goal, optional")
                    case .range:
                        HStack(spacing: 12) {
                            field("Minimum", entry: $lower, bound: .lower)
                            field("Maximum", entry: $upper, bound: .upper)
                        }
                        field("Exact", entry: $exact, bound: .exact)
                    }
                    if mode != .none { NumericKeys(entry: mode == .range ? keyed : $lower, step: 1) }
                    if mode == .range && !valid { Text("Maximum reps must be at least the minimum.").font(.footnote).foregroundStyle(.red) }
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle("Rep Target").inlineTitle()
        }.modifier(KeypadPresentation(height: mode == .range ? 660 : 600))
    }
    private func commit() -> Bool {
        guard valid else { return false }
        guard !edited.hasSameTarget(as: plan) else { return true }
        let target = edited
        guard save(target) else { return false }
        load(target)
        return true
    }
    private var keyed: Binding<KeypadValue> { bound == .upper ? $upper : bound == .exact ? $exact : $lower }
    private func load(_ value: SetPlan) {
        plan = value; mode = RepTargetMode(value); bound = .lower
        lower = .integer(value.reps); upper = .integer(value.repCeiling); exact = .integer(nil)
    }
    private func advance(_ offset: Int) {
        guard commit(), let next = adjacent?(plan.id, offset) else { return }
        load(next)
    }
    private func field(_ title: String, entry: Binding<KeypadValue>, bound value: Bound) -> some View {
        let layout = value == .exact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 6))
        return Button { bound = value; entry.wrappedValue.select() } label: {
            layout {
                Text(title).font(.subheadline)
                if value == .exact { Spacer() }
                Text(entry.wrappedValue.text.isEmpty ? "–" : entry.wrappedValue.text).font((value == .exact ? Font.title2 : .largeTitle).monospacedDigit())
            }.padding(.horizontal, value == .exact ? 16 : 0).frame(maxWidth: .infinity, minHeight: value == .exact ? 44 : 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(bound == value ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(bound == value ? .isSelected : [])
    }
}

/// How a set's weight is set, on the keypad: working weight (with an optional entry), a percentage of it,
/// a fixed load, or none.
struct LoadRuleEditor: View {
    @State var plan: SetPlan
    let unit: WeightUnit
    var suggestedWeight: Double?
    var mode: ExerciseMode = .strength
    let save: (SetPlan) -> Bool
    @State private var original: SetPlan?
    @State private var entry: KeypadValue = .integer(nil)
    private var edited: SetPlan {
        var value = plan
        switch plan.load {
        case .working: value.weightOverride = entry.value.map(unit.kilograms)
        case .percent: value.percent = entry.value ?? 0
        case .fixed: value.fixedWeight = unit.kilograms(entry.value ?? 0)
        case .none: break
        }
        return value
    }
    var body: some View {
        // Changed means a key was pressed or the rule switched; reopening never rewrites a load through display rounding.
        DraftEditor(valid: entry.isValid && edited.isValid, changed: entry.changed || original.map { $0.load != plan.load } == true, save: { save(edited) }) {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Based on", selection: Binding(get: { plan.load }, set: { plan.load = $0; reload() })) {
                        Text("Working").tag(LoadRule.working); Text("Percent").tag(LoadRule.percent)
                        Text("Fixed").tag(LoadRule.fixed); Text(mode == .bodyweight ? "BW" : "None").tag(LoadRule.none)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("load.rule")
                    switch plan.load {
                    case .working:
                        // Empty follows the earlier sets; their weight shows dimmed.
                        NumericDisplay(entry: $entry, title: "Weight (\(unit.rawValue))", placeholder: suggestedWeight.map { number(unit.display($0)) })
                    case .percent: NumericDisplay(entry: $entry, title: "Percent of working set")
                    case .fixed: NumericDisplay(entry: $entry, title: "Weight (\(unit.rawValue))")
                    case .none: EmptyView()
                    }
                    if plan.load != .none { NumericKeys(entry: $entry, step: plan.load == .percent ? 5 : 2.5) }
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle("Weight Settings").inlineTitle()
        }
        .modifier(KeypadPresentation(height: 600))
        .onAppear { if original == nil { original = plan; reload() } }
    }
    private func reload() {
        let signed = mode == .bodyweight
        switch plan.load {
        case .working: entry = .number(NumericEntry(value: plan.weightOverride.map(unit.display), maximum: 100000, integer: false, signed: signed))
        case .percent: entry = .number(NumericEntry(value: plan.percent, maximum: 1000, integer: false))
        case .fixed: entry = .number(NumericEntry(value: unit.display(plan.fixedWeight), maximum: 100000, integer: false, signed: signed))
        case .none: entry = .integer(nil)
        }
    }
}

private struct NumericDisplay: View {
    @Binding var entry: KeypadValue
    let title: String
    var placeholder: String? = nil
    var body: some View {
        HStack {
            if entry.allowsSign {
                Button("±") { entry.press(.sign) }.font(.title2.weight(.medium)).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Change sign")
            }
            Text(entry.text.isEmpty ? placeholder ?? "–" : entry.text).font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(entry.text.isEmpty && placeholder != nil ? .secondary : .primary)
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityLabel("\(title), \(entry.text.isEmpty ? "not set" : entry.text)").accessibilityIdentifier("number.value")
            Button("Clear") { entry.press(.clear) }.frame(minWidth: 44, minHeight: 44)
        }
    }
}

private struct NumericKeys: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool
    @Binding var entry: KeypadValue
    let step: Double
    var presets: [Double] = []
    private var duration: Bool { if case .duration = entry { return true }; return false }
    var body: some View {
        VStack(spacing: 10) {
            if !presets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { value in
                        Button(clockText(value)) { entry.press(.set(value)) }
                            .font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 40).background(palette.wash(.rest), in: Capsule())
                            .buttonStyle(.plain).foregroundStyle(palette.rest)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                ForEach([-2.0, -1, 1, 2], id: \.self) { multiplier in
                    Button { entry.press(.adjust(step * multiplier)) } label: {
                        Text("\(multiplier > 0 ? "+" : "−")\(duration ? clockText(step * abs(multiplier)) : number(step * abs(multiplier)))")
                            .font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(palette.wash(.action), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(palette.action)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", duration ? "00" : ".", "0", "⌫"], id: \.self) { key in
                    Button { key == "⌫" ? entry.press(.backspace) : entry.press(.digit(key)) } label: {
                        Group { if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) } }
                            .font(.title2.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                            .background(palette.field, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(key == "." && !entry.allowsDecimal)
                        .accessibilityLabel(key == "⌫" ? "Backspace" : key == "." ? "Decimal point" : key)
                }
            }
            if !entry.isValid { Text(duration ? "Enter up to \(clockText(entry.maximum))." : "Enter a value up to \(number(entry.maximum)).").font(.footnote).foregroundStyle(palette.failure) }
        }
        .focusable().focused($focused).focusEffectDisabled().onAppear { focused = true }
        .onKeyPress { key in
            if key.key == .delete { entry.press(.backspace); return .handled }
            if key.characters == "-" { entry.press(.sign); return .handled }
            if !key.characters.isEmpty, key.characters.allSatisfy({ "0123456789.,".contains($0) }) { entry.press(.digit(key.characters)); return .handled }
            return .ignored
        }
    }
}

private struct KeypadPresentation: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    var height: CGFloat = 580
    func body(content: Content) -> some View {
        content.frame(idealWidth: 420, idealHeight: height)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(height), .large])
            .presentationDragIndicator(.visible).presentationBackground(palette.card)
    }
}
