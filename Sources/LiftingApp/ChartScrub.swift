import SwiftUI
import Charts

/// Picks a date on a chart: tap a point or slide sideways to scrub. A vertical swipe that starts on the chart
/// scrolls the page; Charts' own selection gestures held the touch and the page wouldn't move.
struct ChartScrub: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    @Binding var date: Date?

    var body: some View {
        let originX = proxy.plotFrame.map { geometry[$0].origin.x } ?? 0
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onTapGesture { location in date = proxy.value(atX: location.x - originX, as: Date.self) }
            .modifier(HorizontalSwipe(changed: { location, _ in date = proxy.value(atX: location.x - originX, as: Date.self) }, ended: {}))
    }
}
