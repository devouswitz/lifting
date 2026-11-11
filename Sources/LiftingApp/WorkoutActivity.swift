#if os(iOS)
import ActivityKit
import Foundation
import LiftingCore

/// Keeps the Lock Screen and Dynamic Island in step with the workout: the next set, the rest countdown,
/// and the time trained. One activity runs per workout; it ends when the workout is finished or discarded.
@MainActor
final class WorkoutActivity {
    private typealias Live = Activity<WorkoutActivityAttributes>
    private struct Target: Equatable {
        var attributes: WorkoutActivityAttributes
        var state: WorkoutActivityAttributes.ContentState
    }
    private var wanted: Target?
    private var applied: Target?
    private var running = false

    /// Shows the workout as it stands now, or ends the activity when there is none. Only the newest state
    /// is sent; a call made while another is being applied replaces it.
    func show(_ data: TrainingData, restStartedAt: Date?) {
        wanted = data.activeSession.map { Target(attributes: Self.attributes($0, data.settings), state: Self.state($0, data, restStartedAt)) }
        guard !running else { return }
        running = true
        Task {
            while true {
                let target = wanted
                await apply(target)
                if wanted == target { break }
            }
            running = false
        }
    }

    private func apply(_ target: Target?) async {
        // Activities outlive the app, so one may be left from an earlier launch.
        let live = Live.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        let current = target.flatMap { target in live.first { $0.attributes == target.attributes } }
        for other in live where other.id != current?.id { await other.end(nil, dismissalPolicy: .immediate) }
        guard let target, ActivityAuthorizationInfo().areActivitiesEnabled else {
            if let current { await current.end(nil, dismissalPolicy: .immediate) }
            applied = nil; return
        }
        // When the rest runs out the content goes stale, which redraws it as "Rest done" with the app suspended.
        let content = ActivityContent(state: target.state, staleDate: target.state.restEnd.flatMap { $0 > Date() ? $0 : nil })
        if let current {
            if applied != target { await current.update(content) }
            applied = target
        } else {
            // Fails when the app is not in front; the next change or return to the app tries again.
            applied = (try? Live.request(attributes: target.attributes, content: content)) == nil ? nil : target
        }
    }

    private static func attributes(_ session: Session, _ settings: LiftingCore.Settings) -> WorkoutActivityAttributes {
        let colors = settings.colors ?? ColorTheme()
        return WorkoutActivityAttributes(name: session.name, restLight: colors.hex(.rest, dark: false), restDark: colors.hex(.rest, dark: true))
    }

    private static func state(_ session: Session, _ data: TrainingData, _ restStartedAt: Date?) -> WorkoutActivityAttributes.ContentState {
        let next = session.nextSet
        let paused = (session.pauses ?? []).reduce(0) { $0 + $1.duration }
        // After a relaunch the rest's start is the set that began it.
        let restStart = restStartedAt ?? session.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
        return .init(exercise: next?.exercise.name, detail: next.map { nextSetText($0, unit: data.settings.unit) },
                     completed: session.completedSets, total: session.totalSets,
                     restStart: data.restDeadline.flatMap { _ in restStart }, restEnd: data.restDeadline,
                     clockStart: session.startedAt.addingTimeInterval(paused),
                     pausedAfter: session.pausedAt.map { _ in session.duration() })
    }
}

/// "Set 3 of 4 · 185 lb × 8", "Warm-up 1 of 2 · 95 lb × 10", "Set 1 of 1 · 20:00".
func nextSetText(_ next: NextSet, unit: WeightUnit) -> String {
    let set = next.set
    var parts = ["\(set.plan.kind == .warmup ? "Warm-up" : "Set") \(next.number) of \(next.count)"]
    let reps = set.reps.map(String.init) ?? set.plan.repTarget.map(displayTarget)
    let load = loadText(set.weight, mode: next.exercise.mode, unit: unit).map { $0 == "BW" ? $0 : "\($0) \(unit.rawValue)" }
    if next.exercise.mode == .cardio {
        parts += [set.seconds.map(clockText), set.meters.map(distanceText)].compactMap { $0 }
    } else if let reps {
        parts.append([load, reps].compactMap { $0 }.joined(separator: " × "))
    } else {
        parts += [load, set.seconds.map(clockText)].compactMap { $0 }
    }
    return parts.joined(separator: " · ")
}
#endif
