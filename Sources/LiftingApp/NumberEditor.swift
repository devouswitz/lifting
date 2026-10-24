import SwiftUI
import LiftingCore

struct NumberEditor: View {
    let edit: NumericEdit
    @State private var entry: NumericEntry
    init(edit: NumericEdit) {
        self.edit = edit
        _entry = State(initialValue: NumericEntry(value: edit.value, maximum: edit.maximum, integer: edit.integer))
    }
    var body: some View {
        DraftEditor(valid: entry.isValid, changed: entry.changed, saveID: "number.done", save: {
            edit.onSave(entry.value); return true
        }) {
            ScrollView {
                VStack(spacing: 12) {
                    if let context = edit.context { Text(context).font(.subheadline).foregroundStyle(.secondary) }
                    NumericDisplay(entry: $entry, title: edit.title)
                    NumericKeys(entry: $entry, step: edit.step)
                }.padding(20)
            }.navigationTitle(edit.title).inlineTitle()
        }.modifier(KeypadPresentation())
    }
}

/// Editing a prescribed range keeps both bounds and the existing target mode.
struct RepValuesEditor: View {
    let plan: SetPlan
    let save: (SetPlan) -> Bool
    @State private var lower: NumericEntry
    @State private var upper: NumericEntry
    @State private var editingUpper = false
    init(plan: SetPlan, save: @escaping (SetPlan) -> Bool) {
        self.plan = plan; self.save = save
        _lower = State(initialValue: NumericEntry(value: plan.reps.map(Double.init), maximum: 10000, integer: true))
        _upper = State(initialValue: NumericEntry(value: plan.repCeiling.map(Double.init), maximum: 10000, integer: true))
    }
    private var isRange: Bool { plan.repRange != nil }
    private var valid: Bool {
        lower.isValid && (!isRange || (upper.isValid && lower.value != nil && upper.value != nil && upper.value! >= lower.value!))
    }
    var body: some View {
        DraftEditor(valid: valid, changed: lower.changed || upper.changed, save: {
            var edited = plan
            edited.reps = lower.value.map(Int.init)
            edited.repCeiling = isRange ? upper.value.map(Int.init) : nil
            return save(edited)
        }) {
            ScrollView {
                VStack(spacing: 12) {
                    if isRange {
                        HStack(spacing: 12) {
                            bound("Minimum", entry: $lower, upper: false)
                            bound("Maximum", entry: $upper, upper: true)
                        }
                    } else { NumericDisplay(entry: $lower, title: "Target reps") }
                    NumericKeys(entry: editingUpper ? $upper : $lower, step: 1)
                    if !valid { Text("Maximum reps must be at least the minimum.").font(.footnote).foregroundStyle(.red) }
                }.padding(20)
            }.navigationTitle(isRange ? "Rep Range" : "Target Reps").inlineTitle()
        }.modifier(KeypadPresentation())
    }
    private func bound(_ title: String, entry: Binding<NumericEntry>, upper: Bool) -> some View {
        Button { editingUpper = upper; entry.wrappedValue.select() } label: {
            VStack(spacing: 6) {
                Text(title).font(.subheadline)
                Text(entry.wrappedValue.text.isEmpty ? "–" : entry.wrappedValue.text).font(.largeTitle.monospacedDigit())
            }.frame(maxWidth: .infinity, minHeight: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(editingUpper == upper ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(editingUpper == upper ? .isSelected : [])
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
    func body(content: Content) -> some View {
        content.frame(idealWidth: 420, idealHeight: 540)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(540), .large])
            .presentationDragIndicator(.visible).presentationBackground(palette.card)
    }
}
