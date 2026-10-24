import SwiftUI

/// Owns a sheet's draft lifetime. Child navigation does not commit the parent draft.
struct DraftEditor<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let valid: Bool
    let changed: Bool
    var saveID = "editor.save"
    let save: () -> Bool
    @ViewBuilder let content: () -> Content
    @State private var resolved = false

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { resolved = true; dismiss() }.keyboardShortcut(.cancelAction)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if save() { resolved = true; dismiss() }
                        }.disabled(!valid).keyboardShortcut(.defaultAction).accessibilityIdentifier(saveID)
                    }
                }
        }
        .interactiveDismissDisabled(!valid && changed)
        .onDisappear {
            guard !resolved, changed, valid else { return }
            resolved = true
            _ = save()
        }
    }
}

/// Editors whose bindings already persist each change still provide the same visible completion action.
struct SaveAndClose: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { dismiss() } } }
    }
}
