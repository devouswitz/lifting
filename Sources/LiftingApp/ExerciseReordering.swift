import SwiftUI
import UniformTypeIdentifiers

struct ExerciseDragHandle: ViewModifier {
    let id: UUID
    let enabled: Bool
    @Binding var dragging: UUID?
    func body(content: Content) -> some View {
        if enabled {
            content.onDrag { dragging = id; return NSItemProvider(object: id.uuidString as NSString) }
                .accessibilityHint("Hold to reorder")
        } else { content }
    }
}

/// Reordering belongs to the item, including when touch dragging is unavailable.
struct ReorderActions: ViewModifier {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    func body(content: Content) -> some View {
        content.accessibilityActions {
            if canMoveUp { Button("Move Up") { move(-1) } }
            if canMoveDown { Button("Move Down") { move(1) } }
        }
    }
}

struct ExerciseDropTarget: ViewModifier {
    @Environment(\.palette) private var palette
    let id: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID, Bool) -> Void
    @State private var height: CGFloat = 60
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .background { GeometryReader { proxy in Color.clear.onAppear { height = proxy.size.height }.onChange(of: proxy.size.height) { height = $1 } } }
            .overlay { RoundedRectangle(cornerRadius: cardRadius).stroke(palette.action, lineWidth: targeted && dragging != id ? 2 : 0).allowsHitTesting(false) }
            .onDrop(of: [UTType.text], isTargeted: $targeted) { providers, location in
                guard let source = dragging, source != id,
                      let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                let after = location.y > height / 2
                dragging = nil
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String, UUID(uuidString: text) == source else { return }
                    Task { @MainActor in withAnimation(.snappy) { move(source, id, after) } }
                }
                return true
            }
    }
}
