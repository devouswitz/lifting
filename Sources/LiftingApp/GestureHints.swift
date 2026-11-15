import SwiftUI
import LiftingCore

/// A gesture with no control to show it is there. Each is taught by one line at the top of a workout or
/// day until the lifter uses the gesture or closes the line; then it never shows again.
enum GestureHint: String, CaseIterable {
    case swipe, reps, weight, badge, quick, rest
    var text: String {
        switch self {
        case .swipe: return "Swipe an exercise's name left to swap or remove it."
        case .reps: return "Hold a reps box to set a target or a range."
        case .weight: return "Hold a weight to make it fixed or a percentage."
        case .badge: return "Hold a set's number for its details."
        case .quick: return "Hold a button beside Add Set to change it."
        case .rest: return "Hold Rest for warm-up and missed-target rest."
        }
    }
    var symbol: String { self == .swipe ? "hand.draw" : "hand.tap" }
    /// The gestures a workout has, in the order they are taught. Cardio has no weights, reps, or quick-add buttons.
    static func workout(lifts: Bool) -> [GestureHint] { lifts ? allCases : [.swipe, .badge, .rest] }
    /// A day sets rep targets with a tap, so it has no hold on reps.
    static func day(lifts: Bool) -> [GestureHint] { workout(lifts: lifts).filter { $0 != .reps } }
}

extension AppStore {
    /// The first of these gestures not yet used or closed, when hints are on.
    func nextHint(among hints: [GestureHint]) -> GestureHint? {
        guard data.settings.showsGestureHints else { return nil }
        let learned = Set(data.settings.learnedGestures ?? [])
        return hints.first { !learned.contains($0.rawValue) }
    }
    /// Records that a gesture was used, or its hint closed, so the hint is not shown again.
    func learn(_ hint: GestureHint) {
        guard !storageBlocked, data.settings.learnedGestures?.contains(hint.rawValue) != true else { return }
        perform { $0.settings.learnedGestures = ($0.settings.learnedGestures ?? []) + [hint.rawValue] }
    }
}

struct GestureHintRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var palette
    let hints: [GestureHint]
    var body: some View {
        let hint = store.nextHint(among: hints)
        Group {
            if let hint {
                HStack(spacing: 10) {
                    Image(systemName: hint.symbol).foregroundStyle(palette.action).frame(width: 22).accessibilityHidden(true)
                    Text(hint.text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.learn(hint) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Hide this hint").accessibilityIdentifier("hint.close")
                }
                .padding(.leading, 6)
                .accessibilityElement(children: .contain).accessibilityIdentifier("hint.\(hint.rawValue)")
                .id(hint).transition(.opacity)
            }
        }.animation(.default, value: hint)
    }
}
