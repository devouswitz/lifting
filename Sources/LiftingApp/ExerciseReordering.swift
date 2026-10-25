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
    /// A row and the rows linked to it, in order. Linked rows lift together and are dropped around, never between.
    var linked: (UUID) -> [UUID] = { [$0] }
    let place: (_ source: UUID, _ target: UUID, _ after: Bool) -> Void

    /// For a card shown alone, with nothing to reorder against.
    static let none = Reordering(space: "none", lifted: .constant(nil), rows: RowFrames()) { _, _, _ in }

    /// The row under the finger, and whether the lifted row goes after it.
    func target(for lifted: LiftedRow) -> (id: UUID, after: Bool)? {
        let moving = linked(lifted.id)
        guard let hit = rows.frames.first(where: { !moving.contains($0.key) && ($0.value.minY...$0.value.maxY).contains(lifted.location.y) }) else { return nil }
        let after = lifted.location.y > hit.value.midY
        let group = linked(hit.key)
        return ((after ? group.last : group.first) ?? hit.key, after)
    }
}

extension View {
    /// A scroll view holding reorderable rows. The hold that lifts a row runs alongside scrolling, so a swipe that
    /// starts on a handle still scrolls; scrolling pauses only while a row is lifted, so the page stays under the finger.
    func reorderingScroll() -> some View { modifier(ReorderingScroll()) }

    /// The stack that owns a reordering.
    func reorderingStack(_ space: String) -> some View { coordinateSpace(.named(space)) }

    /// A row that can be reordered: reports its frame, follows the finger while lifted, and outlines itself as the drop target.
    func reorderRow(_ id: UUID, _ reordering: Reordering) -> some View { modifier(ReorderRow(id: id, reordering: reordering)) }

    /// Hold, then drag, to move the row. Only a hold starts it, so taps and scrolling pass through.
    /// A hold released without moving runs `hold` instead, when one is given.
    func reorderHandle(_ id: UUID, _ reordering: Reordering, enabled: Bool = true, hold: (() -> Void)? = nil) -> some View {
        modifier(ReorderHandle(id: id, reordering: reordering, enabled: enabled, hold: hold))
    }
}

/// Whether any row inside is lifted. Rows nest (sets inside exercises), so each one adds to its children's value.
private struct RowLiftedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct ReorderingScroll: ViewModifier {
    @State private var locked = false
    func body(content: Content) -> some View {
        content.scrollDisabled(locked).onPreferenceChange(RowLiftedKey.self) { locked = $0 }
    }
}

private struct ReorderRow: ViewModifier {
    @Environment(\.palette) private var palette
    let id: UUID
    let reordering: Reordering
    func body(content: Content) -> some View {
        let lifted = reordering.lifted
        let isLifted = lifted.map { reordering.linked($0.id).contains(id) } ?? false
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
            .transformPreference(RowLiftedKey.self) { $0 = $0 || isLifted }
    }
}

private struct ReorderHandle: ViewModifier {
    let id: UUID
    let reordering: Reordering
    let enabled: Bool
    let hold: (() -> Void)?
    /// True while the hold-and-drag is in progress; resets on its own if the system cancels the gesture.
    @GestureState private var active = false
    func body(content: Content) -> some View {
        if enabled {
            holdToDrag(content)
                .sensoryFeedback(.impact(weight: .medium), trigger: reordering.lifted?.id == id) { _, lifted in lifted }
                .accessibilityHint("Hold and drag to reorder")
        } else { content }
    }

    @ViewBuilder private func holdToDrag(_ content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            // UIKit's long press runs alongside the scroll view. SwiftUI's LongPressGesture keeps a swipe that starts on
            // the handle from scrolling, which made a day of collapsed exercises nearly impossible to scroll.
            content.gesture(HoldRecognizer(space: reordering.space, moved: move, released: release))
        } else { swiftUIHold(content) }
        #else
        swiftUIHold(content)
        #endif
    }

    private func swiftUIHold(_ content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(reordering.space)))
                .updating($active) { _, active, _ in active = true }
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    move(drag?.location ?? reordering.rows.frames[id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero, drag?.translation.height ?? 0)
                }
                .onEnded { value in
                    guard case .second(true, let drag) = value else { return }
                    release(drag?.location ?? .zero, drag?.translation.height ?? 0, cancelled: false)
                }
        )
        .onChange(of: active) { _, active in if !active, reordering.lifted?.id == id { reordering.lifted = nil } }
    }

    private func move(_ location: CGPoint, _ offset: CGFloat) { reordering.lifted = LiftedRow(id: id, offset: offset, location: location) }

    /// A hold released without moving runs `hold`; otherwise the row lands where the finger lifts.
    private func release(_ location: CGPoint, _ offset: CGFloat, cancelled: Bool) {
        reordering.lifted = nil
        guard !cancelled else { return }
        if let hold, abs(offset) < 6 { hold(); return }
        if let target = reordering.target(for: LiftedRow(id: id, offset: offset, location: location)) {
            withAnimation(.snappy) { reordering.place(id, target.id, target.after) }
        }
    }
}

#if os(iOS)
/// One UIKit long press covers the hold, the drag after it, and the release, reported in the stack's coordinate space.
@available(iOS 18, *)
private struct HoldRecognizer: UIGestureRecognizerRepresentable {
    let space: String
    let moved: (CGPoint, CGFloat) -> Void
    let released: (CGPoint, CGFloat, _ cancelled: Bool) -> Void
    final class Coordinator { var startY: CGFloat = 0 }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }
    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .named(space))
        if recognizer.state == .began { context.coordinator.startY = location.y }
        let offset = location.y - context.coordinator.startY
        switch recognizer.state {
        case .began, .changed: moved(location, offset)
        case .ended: released(location, offset, false)
        case .cancelled, .failed: released(location, offset, true)
        default: break
        }
    }
}
#endif

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
