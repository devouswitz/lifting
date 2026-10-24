import SwiftUI
import LiftingCore

struct NumericEdit: Identifiable {
    let id = UUID()
    let title: String
    var context: String? = nil
    let value: Double?
    let step: Double
    let maximum: Double
    let integer: Bool
    var previous: (() -> NumericEdit?)? = nil
    var next: (() -> NumericEdit?)? = nil
    let onSave: (Double?) -> Bool
}

/// A keypad stays open while moving through sets. Only edited values become overrides.
struct NumberEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var edit: NumericEdit
    @State private var entry: NumericEntry
    @State private var resolved = false
    init(edit: NumericEdit) {
        _edit = State(initialValue: edit)
        _entry = State(initialValue: NumericEntry(value: edit.value, maximum: edit.maximum, integer: edit.integer))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let context = edit.context { Text(context).font(.subheadline).foregroundStyle(.secondary) }
                    if edit.previous != nil || edit.next != nil {
                        HStack {
                            Button("Previous Set", systemImage: "chevron.left") { advance(edit.previous) }.disabled(edit.previous == nil)
                            Spacer()
                            Button("Next Set", systemImage: "chevron.right") { advance(edit.next) }.disabled(edit.next == nil)
                        }.font(.subheadline).buttonStyle(.plain).frame(minHeight: 44).disabled(!entry.isValid)
                    }
                    NumericDisplay(entry: $entry, title: edit.title)
                    NumericKeys(entry: $entry, step: edit.step)
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle(edit.title).inlineTitle()
                .toolbar {
                    if !entry.isValid { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { resolved = true; dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close", systemImage: "xmark") { if commit() { resolved = true; dismiss() } }
                            .labelStyle(.iconOnly).disabled(!entry.isValid).keyboardShortcut(.cancelAction)
                    }
                }
        }
        .interactiveDismissDisabled(!entry.isValid)
        .onDisappear { if !resolved { _ = commit() } }
        .modifier(KeypadPresentation())
    }
    private func commit() -> Bool {
        guard entry.isValid else { return false }
        guard entry.changed else { return true }
        guard edit.onSave(entry.value) else { return false }
        entry = NumericEntry(value: entry.value, maximum: edit.maximum, integer: edit.integer)
        return true
    }
    private func advance(_ destination: (() -> NumericEdit?)?) {
        guard commit(), let next = destination?() else { return }
        edit = next
        entry = NumericEntry(value: next.value, maximum: next.maximum, integer: next.integer)
    }
}

/// Ranges retain both bounds. Navigation commits a complete valid target, never a partial range.
struct RepValuesEditor: View {
    @State var plan: SetPlan
    let save: (SetPlan) -> Bool
    var adjacent: ((UUID, Int) -> SetPlan?)? = nil
    @State private var exact: NumericEntry
    @State private var lower: NumericEntry
    @State private var upper: NumericEntry
    private enum Bound { case exact, lower, upper }
    @State private var selection = Bound.lower
    init(plan: SetPlan, save: @escaping (SetPlan) -> Bool, adjacent: ((UUID, Int) -> SetPlan?)? = nil) {
        _plan = State(initialValue: plan); self.save = save; self.adjacent = adjacent
        _exact = State(initialValue: NumericEntry(value: nil, maximum: 10000, integer: true))
        _lower = State(initialValue: NumericEntry(value: plan.reps.map(Double.init), maximum: 10000, integer: true))
        _upper = State(initialValue: NumericEntry(value: plan.repCeiling.map(Double.init), maximum: 10000, integer: true))
    }
    private var isRange: Bool { plan.repRange != nil }
    private var usesExact: Bool { isRange && selection == .exact }
    private var changed: Bool { usesExact ? exact.changed : lower.changed || upper.changed }
    private var valid: Bool {
        if usesExact { return exact.isValid && (!exact.changed || exact.value != nil) }
        return lower.isValid && (!isRange || (upper.isValid && lower.value != nil && upper.value != nil && upper.value! >= lower.value!))
    }
    private var selectedEntry: Binding<NumericEntry> { selection == .exact ? $exact : selection == .upper ? $upper : $lower }
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
                    } else { NumericDisplay(entry: $lower, title: "Target reps") }
                    NumericKeys(entry: selectedEntry, step: 1)
                    if !valid && !usesExact { Text("Maximum reps must be at least the minimum.").font(.footnote).foregroundStyle(.red) }
                    StoreErrorRow()
                }.padding(20)
            }.navigationTitle(isRange ? "Rep Range" : "Target Reps").inlineTitle()
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
        exact = NumericEntry(value: nil, maximum: 10000, integer: true)
        lower = NumericEntry(value: value.reps.map(Double.init), maximum: 10000, integer: true)
        upper = NumericEntry(value: value.repCeiling.map(Double.init), maximum: 10000, integer: true)
    }
    private func advance(_ offset: Int) {
        guard commit(), let next = adjacent?(plan.id, offset) else { return }
        load(next)
    }
    private func bound(_ title: String, entry: Binding<NumericEntry>, selection bound: Bound) -> some View {
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
    @Binding var entry: NumericEntry
    let title: String
    var body: some View {
        HStack {
            Text(entry.text.isEmpty ? "–" : entry.text).font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityLabel("\(title), \(entry.text.isEmpty ? "not set" : entry.text)").accessibilityIdentifier("number.value")
            Button("Clear") { entry.clear() }.frame(minWidth: 44, minHeight: 44)
        }
    }
}

private struct NumericKeys: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool
    @Binding var entry: NumericEntry
    let step: Double
    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                ForEach([-2.0, -1, 1, 2], id: \.self) { multiplier in
                    Button { entry.adjust(by: step * multiplier) } label: {
                        Text("\(multiplier > 0 ? "+" : "−")\(number(step * abs(multiplier)))")
                            .font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(palette.wash(.action), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(palette.action)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                    Button { if key == "⌫" { entry.backspace() } else { entry.insert(key) } } label: {
                        Group { if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) } }
                            .font(.title2.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                            .background(palette.field, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(key == "." && entry.integer)
                        .accessibilityLabel(key == "⌫" ? "Backspace" : key == "." ? "Decimal point" : key)
                }
            }
            if !entry.isValid { Text("Enter a value from 0 to \(number(entry.maximum)).").font(.footnote).foregroundStyle(palette.failure) }
        }
        .focusable().focused($focused).focusEffectDisabled().onAppear { focused = true }
        .onKeyPress { key in
            if key.key == .delete { entry.backspace(); return .handled }
            if !key.characters.isEmpty, key.characters.allSatisfy({ "0123456789.,".contains($0) }) { entry.insert(key.characters); return .handled }
            return .ignored
        }
    }
}

private struct KeypadPresentation: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    var height: CGFloat = 540
    func body(content: Content) -> some View {
        content.frame(idealWidth: 420, idealHeight: height)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(height), .large])
            .presentationDragIndicator(.visible).presentationBackground(palette.card)
    }
}
