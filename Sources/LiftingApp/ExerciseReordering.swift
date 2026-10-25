import SwiftUI

/// A row being held and dragged: which one, how far it has moved, and where the finger is.
struct LiftedRow: Equatable {
    var id: UUID
    var offset: CGFloat
    var location: CGPoint
}

/// Where each row sits. Rows write into it as they lay out; reading it never redraws anything, so row
/// positions can't feed back into layout.
final class RowFrames {
    var frames: [UUID: CGRect] = [:]
}

/// Hold and drag to reorder rows in a stack. The stack owns this: it names a coordinate space, keeps the
/// row positions, and applies a move when a row is dropped. Unlike system drag and drop, nothing leaves the app,
/// so a drag always lands where the finger lifts.
struct Reordering {
    let space: String
    @Binding var lifted: LiftedRow?
    let rows: RowFrames
    let place: (_ source: UUID, _ target: UUID, _ after: Bool) -> Void

    /// For a card shown alone, with nothing to reorder against.
    static let none = Reordering(space: "none", lifted: .constant(nil), rows: RowFrames()) { _, _, _ in }

    /// The row under the finger, and whether the lifted row goes after it.
    func target(for lifted: LiftedRow) -> (id: UUID, after: Bool)? {
        guard let hit = rows.frames.first(where: { $0.key != lifted.id && ($0.value.minY...$0.value.maxY).contains(lifted.location.y) }) else { return nil }
        return (hit.key, lifted.location.y > hit.value.midY)
    }
}

extension View {
    /// The stack that owns a reordering.
    func reorderingStack(_ space: String) -> some View { coordinateSpace(.named(space)) }

    /// A row that can be reordered: reports its frame, follows the finger while lifted, and outlines itself as the drop target.
    func reorderRow(_ id: UUID, _ reordering: Reordering) -> some View { modifier(ReorderRow(id: id, reordering: reordering)) }

    /// Hold, then drag, to move the row. Only a hold starts it, so taps and scrolling pass through.
    func reorderHandle(_ id: UUID, _ reordering: Reordering, enabled: Bool = true) -> some View {
        modifier(ReorderHandle(id: id, reordering: reordering, enabled: enabled))
    }
}

private struct ReorderRow: ViewModifier {
    @Environment(\.palette) private var palette
    let id: UUID
    let reordering: Reordering
    func body(content: Content) -> some View {
        let lifted = reordering.lifted
        let isLifted = lifted?.id == id
        let target = lifted.flatMap { reordering.target(for: $0) }
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(reordering.space)) } action: { reordering.rows.frames[id] = $0 }
            .onDisappear { reordering.rows.frames[id] = nil }
            .overlay(alignment: target?.after == true ? .bottom : .top) {
                if target?.id == id { Capsule().fill(palette.action).frame(height: 3).padding(.horizontal, 8).offset(y: target?.after == true ? 6 : -6).allowsHitTesting(false) }
            }
            .offset(y: isLifted ? lifted?.offset ?? 0 : 0)
            .scaleEffect(isLifted ? 1.02 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.2 : 0), radius: 12, y: 4)
            .zIndex(isLifted ? 1 : 0)
            .animation(.snappy(duration: 0.2), value: isLifted)
    }
}

private struct ReorderHandle: ViewModifier {
    let id: UUID
    let reordering: Reordering
    let enabled: Bool
    /// True while the hold-and-drag is in progress; resets on its own if the system cancels the gesture.
    @GestureState private var active = false
    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(reordering.space)))
                    .updating($active) { _, active, _ in active = true }
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        reordering.lifted = LiftedRow(id: id, offset: drag?.translation.height ?? 0, location: drag?.location ?? reordering.rows.frames[id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero)
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value,
                           let target = reordering.target(for: LiftedRow(id: id, offset: drag.translation.height, location: drag.location)) {
                            withAnimation(.snappy) { reordering.place(id, target.id, target.after) }
                        }
                        reordering.lifted = nil
                    }
            )
            .onChange(of: active) { _, active in if !active, reordering.lifted?.id == id { reordering.lifted = nil } }
            .sensoryFeedback(.impact(weight: .medium), trigger: reordering.lifted?.id == id) { _, lifted in lifted }
            .accessibilityHint("Hold and drag to reorder")
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
