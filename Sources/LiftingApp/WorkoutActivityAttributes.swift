#if os(iOS)
import ActivityKit
import Foundation

/// What the Lock Screen and Dynamic Island show during a workout. This file is compiled into both the
/// app and its Live Activity extension, so it depends on nothing else.
struct WorkoutActivityAttributes: ActivityAttributes, Equatable {
    struct ContentState: Codable, Hashable {
        /// The exercise to do next and its next set, "Set 3 of 4 · 185 lb × 8". Nil once every set is logged.
        var exercise: String?
        var detail: String?
        var completed: Int
        var total: Int
        /// The rest that is running or has run out. Nil between rests.
        var restStart: Date?
        var restEnd: Date?
        /// The workout's start moved forward by its pauses, so a timer from here reads the time trained.
        var clockStart: Date
        /// The time trained, while the workout is paused.
        var pausedAfter: TimeInterval?
    }
    var name: String
    /// The app's rest color for each appearance, as 0xRRGGBB.
    var restLight: UInt32
    var restDark: UInt32
}
#endif
