import SwiftUI

/// Swipe actions for set tables, which live inside cards rather than a List.
struct SwipeToDelete<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var origin: CGFloat = 0
    @State private var axis: Axis?
    @State private var width: CGFloat = 320

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash.fill").foregroundStyle(.white)
                        .frame(width: max(76, -offset)).frame(maxHeight: .infinity)
                        .background(Color.red)
                }.buttonStyle(.plain).accessibilityLabel("Delete set")
            }
            content
                .disabled(axis == .horizontal || offset < 0)
                .overlay { if offset < 0 { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .background { GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { width = $1 } } }
        // Runs alongside the scroll view: a vertical drag scrolls, a horizontal one swipes, and the first
        // direction decides so a scroll never nudges the row sideways.
        .simultaneousGesture(DragGesture(minimumDistance: 12)
            .onChanged { value in
                if axis == nil {
                    let x = abs(value.translation.width), y = abs(value.translation.height)
                    if x > y * 1.5 { axis = .horizontal }
                    else if y > x * 1.5 { axis = .vertical }
                }
                guard axis == .horizontal else { return }
                offset = min(0, max(-width, origin + value.translation.width))
            }
            .onEnded { _ in
                defer { axis = nil }
                guard axis == .horizontal else { return }
                if -offset >= min(180, width * 0.55) { remove() }
                else { withAnimation(.snappy) { offset = offset < -38 ? -76 : 0; origin = offset } }
            })
        .accessibilityAction(named: "Delete set", action)
    }

    private func close() { withAnimation(.snappy) { offset = 0; origin = 0 } }
    private func remove() { withAnimation(.snappy) { action(); offset = 0; origin = 0 } }
}
