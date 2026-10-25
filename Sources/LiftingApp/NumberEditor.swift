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

/// Ranges retain both bounds. Navigation commits a complete valid target, never a partial range.
struct RepValuesEditor: View {
    @State var plan: SetPlan
    let save: (SetPlan) -> Bool
    var adjacent: ((UUID, Int) -> SetPlan?)? = nil
    @State private var exact: KeypadValue
    @State private var lower: KeypadValue
    @State private var upper: KeypadValue
    private enum Bound { case exact, lower, upper }
    @State private var selection = Bound.lower
    init(plan: SetPlan, save: @escaping (SetPlan) -> Bool, adjacent: ((UUID, Int) -> SetPlan?)? = nil) {
        _plan = State(initialValue: plan); self.save = save; self.adjacent = adjacent
        _exact = State(initialValue: .integer(nil))
        _lower = State(initialValue: .integer(plan.reps))
        _upper = State(initialValue: .integer(plan.repCeiling))
    }
    private var isRange: Bool { plan.repRange != nil }
    private var usesExact: Bool { isRange && selection == .exact }
    private var changed: Bool { usesExact ? exact.changed : lower.changed || upper.changed }
    private var valid: Bool {
        if usesExact { return exact.isValid && (!exact.changed || exact.value != nil) }
        return lower.isValid && (!isRange || (upper.isValid && lower.value != nil && upper.value != nil && upper.value! >= lower.value!))
    }
    private var selectedEntry: Binding<KeypadValue> { selection == .exact ? $exact : selection == .upper ? $upper : $lower }
    var body: some View {
        DraftEditor(valid: valid, changed: changed, save: commit) {
            ScrollView {
                VStack(spacing: 12) {
                    if isRange { bound("Exact reps", entry: $exact, selection: .exact) }
                    if let adjacent {
                        HStack {
                            Button("Previous Set", systemImage: "chevron.left") { advance(-1) }.disabled(adjacent(plan.id, -1) == nil)
                            Spacer()
                            Button("Next Set", systemImage: "chevron.right") { advance(1) }.disabled(adjacent(plan.id, 1) == nil)
                        }.font(.subheadline).buttonStyle(.plain).frame(minHeight: 44).disabled(!valid)
                    }
                    if isRange {
                        HStack(spacing: 12) {
                            bound("Minimum", entry: $lower, selection: .lower)
                            bound("Maximum", entry: $upper, selection: .upper)
                        }
                    } else { NumericDisplay(entry: $lower, title: plan.amrap ? "AMRAP goal" : "Target reps") }
                    NumericKeys(entry: selectedEntry, step: 1)
                    if !valid && !usesExact { Text("Maximum reps must be at least the minimum.").font(.footnote).foregroundStyle(.red) }
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle(isRange ? "Rep Range" : plan.amrap ? "AMRAP" : "Target Reps").inlineTitle()
        }.modifier(KeypadPresentation(height: isRange ? 620 : 540))
    }
    private func commit() -> Bool {
        guard valid else { return false }
        guard changed else { return true }
        var edited = plan
        edited.reps = (usesExact ? exact.value : lower.value).map(Int.init)
        edited.repCeiling = isRange && !usesExact ? upper.value.map(Int.init) : nil
        guard save(edited) else { return false }
        load(edited)
        return true
    }
    private func load(_ value: SetPlan) {
        plan = value; selection = .lower
        exact = .integer(nil); lower = .integer(value.reps); upper = .integer(value.repCeiling)
    }
    private func advance(_ offset: Int) {
        guard commit(), let next = adjacent?(plan.id, offset) else { return }
        load(next)
    }
    private func bound(_ title: String, entry: Binding<KeypadValue>, selection bound: Bound) -> some View {
        let layout = bound == .exact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 6))
        return Button { selection = bound; entry.wrappedValue.select() } label: {
            layout {
                Text(title).font(.subheadline)
                if bound == .exact { Spacer() }
                Text(entry.wrappedValue.text.isEmpty ? "–" : entry.wrappedValue.text).font((bound == .exact ? Font.title2 : .largeTitle).monospacedDigit())
            }.padding(.horizontal, bound == .exact ? 16 : 0).frame(maxWidth: .infinity, minHeight: bound == .exact ? 44 : 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selection == bound ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(selection == bound ? .isSelected : [])
    }
}

private struct NumericDisplay: View {
    @Binding var entry: KeypadValue
    let title: String
    var body: some View {
        HStack {
            if entry.allowsSign {
                Button("±") { entry.press(.sign) }.font(.title2.weight(.medium)).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Change sign")
            }
            Text(entry.text.isEmpty ? "–" : entry.text).font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
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
