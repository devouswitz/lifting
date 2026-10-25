import SwiftUI

extension View {
    /// A hold that opens a value's extra settings, also offered as a named accessibility action.
    func longPress(_ label: String, perform action: @escaping () -> Void) -> some View {
        highPriorityGesture(LongPressGesture().onEnded { _ in action() }).accessibilityAction(named: label, action)
    }
}
