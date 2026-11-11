import SwiftUI

/// A second action revealed by a short swipe, beside Delete.
struct SwipeAction {
    let title: String
    let symbol: String
    let run: () -> Void
}

/// Swipe actions for rows that live inside cards rather than a List: set rows and exercise headers.
/// A short swipe reveals the actions; swiping on past them deletes.
struct SwipeToDelete<Content: View>: View {
    @Environment(\.palette) private var palette
    var deleteLabel = "Delete set"
    var secondary: SwipeAction? = nil
    /// The actions slide in over the row's trailing side and the row stays put, so its name stays readable.
    var covers = false
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var origin: CGFloat = 0
    @State private var axis: Axis?
    @State private var width: CGFloat = 320
    private let slot: CGFloat = 76
    /// Where the row rests with its actions showing, and how far a swipe must go to delete outright.
    private var open: CGFloat { secondary == nil ? slot : slot * 2 }
    private var full: CGFloat { max(open + 44, min(220, width * 0.6)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if !covers { actions }
            content
                .disabled(axis == .horizontal || offset < 0)
                .overlay { if offset < 0 { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }
                .offset(x: covers ? 0 : offset)
            if covers { actions }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .background { GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { width = $1 } } }
        .modifier(HorizontalSwipe(changed: { _, translation in changed(translation) }, ended: ended))
        .accessibilityAction(named: deleteLabel, action)
        .modifier(SecondaryAccessibilityAction(action: secondary))
    }

    @ViewBuilder private var actions: some View {
        if offset < 0 {
            // Past the full-swipe point Delete takes the whole strip, showing what letting go will do.
            let side = -offset >= full ? 0 : min(slot, -offset / 2)
            HStack(spacing: 0) {
                if let secondary, side > 0 {
                    Button { close(); secondary.run() } label: {
                        Image(systemName: secondary.symbol).foregroundStyle(palette.on(.action))
                            .frame(width: side).frame(maxHeight: .infinity).background(palette.action)
                    }.buttonStyle(.plain).accessibilityLabel(secondary.title)
                }
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash.fill").foregroundStyle(.white)
                        .frame(width: max(slot, -offset - (secondary == nil ? 0 : side))).frame(maxHeight: .infinity)
                        .background(Color.red)
                }.buttonStyle(.plain).accessibilityLabel(deleteLabel)
            }
            // Covering the row, the strip is only as wide as the swipe so far, so it slides in from the edge.
            .frame(width: covers ? -offset : nil, alignment: .leading).clipped()
            .animation(.snappy(duration: 0.2), value: -offset >= full)
        }
    }

    /// The first direction decides, so a scroll never nudges the row sideways.
    private func changed(_ translation: CGSize) {
        if axis == nil {
            let x = abs(translation.width), y = abs(translation.height)
            if x > y * 1.5 { axis = .horizontal }
            else if y > x * 1.5 { axis = .vertical }
        }
        guard axis == .horizontal else { return }
        offset = min(0, max(-width, origin + translation.width))
    }
    private func ended() {
        defer { axis = nil }
        guard axis == .horizontal else { return }
        if -offset >= full { remove() }
        else { withAnimation(.snappy) { offset = offset < -38 ? -open : 0; origin = offset } }
    }

    private func close() { withAnimation(.snappy) { offset = 0; origin = 0 } }
    private func remove() { withAnimation(.snappy) { action(); offset = 0; origin = 0 } }
}

private struct SecondaryAccessibilityAction: ViewModifier {
    let action: SwipeAction?
    func body(content: Content) -> some View {
        if let action { content.accessibilityAction(named: action.title, action.run) } else { content }
    }
}

/// A sideways drag, reported as the finger's location and how far it has moved. On iOS 18 and later it is a UIKit
/// pan that only begins when the finger moves more sideways than up or down, so a vertical swipe goes to the scroll
/// view untouched. SwiftUI's DragGesture ran alongside the scroll view and made swipes that started on a set row
/// or a chart stutter or stall.
struct HorizontalSwipe: ViewModifier {
    let changed: (_ location: CGPoint, _ translation: CGSize) -> Void
    let ended: () -> Void
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) { content.gesture(SidewaysPan(changed: changed, ended: ended)) } else { dragGesture(content) }
        #else
        dragGesture(content)
        #endif
    }
    private func dragGesture(_ content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 12)
            .onChanged { changed($0.location, $0.translation) }
            .onEnded { _ in ended() })
    }
}

#if os(iOS)
@available(iOS 18, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let changed: (CGPoint, CGSize) -> Void
    let ended: () -> Void
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }
        /// The scroll view decides after this pan does; both wait for the same movement, so scrolling isn't delayed.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: recognizer.view)
            changed(context.converter.localLocation, CGSize(width: translation.x, height: translation.y))
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }
}
#endif
