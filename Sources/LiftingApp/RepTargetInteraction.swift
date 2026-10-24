import SwiftUI

struct RepTargetInteraction: ViewModifier {
    let enabled: Bool
    let edit: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(LongPressGesture().onEnded { _ in edit() })
                .accessibilityAction(named: "Edit rep target", edit)
        } else { content }
    }
}

struct WeightSettingsInteraction: ViewModifier {
    let enabled: Bool
    let edit: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(LongPressGesture().onEnded { _ in edit() })
                .accessibilityAction(named: "Weight settings", edit)
        } else { content }
    }
}
