import SwiftUI

/// A numeric row owns its full tap target, while the native field keeps selection and paste.
struct NumberRow: View {
    let title: String
    @Binding var value: Double?
    var placeholder = "Optional"
    var factor: Double = 1
    var integer = false
    @State private var focused = false

    init(_ title: String, value: Binding<Double?>, placeholder: String = "Optional", factor: Double = 1, integer: Bool = false) {
        self.title = title; _value = value; self.placeholder = placeholder; self.factor = factor; self.integer = integer
    }
    init(_ title: String, value: Binding<Double>, factor: Double = 1) {
        self.init(title, value: Binding(get: { value.wrappedValue }, set: { if let valueToSave = $0 { value.wrappedValue = valueToSave } }), placeholder: "0", factor: factor)
    }
    init(_ title: String, value: Binding<Int>) {
        self.init(title, value: Binding(get: { Double(value.wrappedValue) }, set: { if let valueToSave = $0 { value.wrappedValue = Int(valueToSave) } }), placeholder: "0", integer: true)
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            NumberField(title: title, value: $value, placeholder: placeholder, factor: factor, integer: integer, focused: $focused)
                .frame(minWidth: 88, maxWidth: 140)
        }.frame(minHeight: 44).contentShape(Rectangle()).onTapGesture { focused = true }
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var placeholder = "Optional"
    var factor: Double = 1
    var integer = false
    @Binding var focused: Bool
    @State private var text = ""

    var body: some View {
        NativeNumberInput(text: $text, focused: $focused, title: title, placeholder: placeholder, integer: integer)
            .frame(minHeight: 44)
            .onAppear { sync() }
            .onChange(of: value) { _, _ in if !focused { sync() } }
            .onChange(of: text) { _, new in
                if new == (value.map { number($0 / factor, decimals: 3) } ?? "") { return }
                if new.isEmpty { value = nil }
                else if let parsed = Double(new.replacingOccurrences(of: ",", with: ".")), parsed.isFinite,
                        parsed >= 0, (parsed * factor).isFinite, !integer || parsed.rounded() == parsed {
                    value = parsed * factor
                }
            }
            .onChange(of: focused) { _, active in if !active { sync() } }
    }
    private func sync() { text = value.map { number($0 / factor, decimals: 3) } ?? "" }
}

#if os(iOS)
import UIKit

struct NativeNumberInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let title: String
    let placeholder: String
    let integer: Bool
    var large = false

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.textAlignment = .right
        field.font = .preferredFont(forTextStyle: large ? .largeTitle : .body)
        field.adjustsFontForContentSizeCategory = true
        field.keyboardType = integer ? .numberPad : .decimalPad
        field.clearButtonMode = .whileEditing
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let bar = UIToolbar()
        bar.items = [.flexibleSpace(), UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak field] _ in field?.resignFirstResponder() })]
        bar.sizeToFit()
        field.inputAccessoryView = bar
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.accessibilityLabel = title
        if focused && !field.isFirstResponder {
            DispatchQueue.main.async { if focused && field.window != nil { field.becomeFirstResponder() } }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeNumberInput
        init(_ parent: NativeNumberInput) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.focused = true
            DispatchQueue.main.async { if field.isFirstResponder { field.selectAll(nil) } }
        }
        func textFieldDidEndEditing(_ field: UITextField) { parent.focused = false }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString replacement: String) -> Bool {
            guard let range = Range(range, in: field.text ?? "") else { return false }
            let proposed = (field.text ?? "").replacingCharacters(in: range, with: replacement)
            return validNumericText(proposed, integer: parent.integer)
        }
    }
}
#else
import AppKit

struct NativeNumberInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let title: String
    let placeholder: String
    let integer: Bool
    var large = false
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false; field.drawsBackground = false
        field.alignment = .right; field.font = .preferredFont(forTextStyle: large ? .largeTitle : .body)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(title)
        if focused && field.currentEditor() == nil {
            DispatchQueue.main.async { if focused { field.window?.makeFirstResponder(field) } }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeNumberInput
        init(_ parent: NativeNumberInput) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focused = true
            (notification.object as? NSTextField)?.currentEditor()?.selectAll(nil)
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if validNumericText(field.stringValue, integer: parent.integer) { parent.text = field.stringValue }
            else { field.stringValue = parent.text }
        }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
    }
}
#endif

private func validNumericText(_ text: String, integer: Bool) -> Bool {
    text.count <= 14 && text.allSatisfy { "0123456789".contains($0) || (!integer && ".,".contains($0)) }
        && text.filter { ".,".contains($0) }.count <= 1
}
