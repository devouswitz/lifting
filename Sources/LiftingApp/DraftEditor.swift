import SwiftUI

/// Existing records commit on dismissal; creation and batch commands require confirmation.
/// Child navigation never commits the parent draft.
struct DraftEditor<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let valid: Bool
    let changed: Bool
    var saveID = "editor.save"
    var confirmation: String? = nil
    let save: () -> Bool
    @ViewBuilder let content: () -> Content
    @State private var resolved = false

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if confirmation != nil || (!valid && changed) {
                            Button("Cancel") { resolved = true; dismiss() }.keyboardShortcut(.cancelAction)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if let confirmation {
                            Button(confirmation, action: finish).disabled(!valid)
                                .keyboardShortcut(.defaultAction).accessibilityIdentifier(saveID)
                        } else {
                            // Closing keeps the edits, so it reads as done rather than dismiss.
                            Button("Done", systemImage: "checkmark", action: finish).labelStyle(.iconOnly)
                                .disabled(!valid).keyboardShortcut(.cancelAction)
                        }
                    }
                }
        }
        .interactiveDismissDisabled(!valid && changed)
        .onDisappear {
            guard confirmation == nil, !resolved, changed, valid else { return }
            resolved = true
            _ = save()
        }
    }
    private func finish() {
        guard confirmation != nil || changed else { resolved = true; dismiss(); return }
        if save() { resolved = true; dismiss() }
    }
}
