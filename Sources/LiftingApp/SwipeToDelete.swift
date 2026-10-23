import SwiftUI

/// Swipe actions for set tables, which live inside cards rather than a List.
struct SwipeToDelete<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var origin: CGFloat = 0
    @State private var horizontal = false
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
                .overlay { if offset < 0 { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .background { GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width }.onChange(of: proxy.size.width) { width = $1 } } }
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .onChanged { value in
                if !horizontal {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    horizontal = true
                }
                offset = min(0, max(-width, origin + value.translation.width))
            }
            .onEnded { _ in
                defer { horizontal = false }
                guard horizontal else { return }
                if -offset > max(150, width * 0.65) { remove() }
                else { withAnimation(.snappy) { offset = offset < -38 ? -76 : 0; origin = offset } }
            })
        .accessibilityAction(named: "Delete set", action)
    }

    private func close() { withAnimation(.snappy) { offset = 0; origin = 0 } }
    private func remove() { withAnimation(.snappy) { action(); offset = 0; origin = 0 } }
}
