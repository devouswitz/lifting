import SwiftUI

struct RepTargetInteraction: ViewModifier {
    let enabled: Bool
    let edit: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { Button("Edit Rep Target", action: edit) }
                .accessibilityAction(named: "Edit rep target", edit)
        } else { content }
    }
}
