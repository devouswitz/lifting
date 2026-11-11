import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SetformLiveBundle: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

/// The workout on the Lock Screen and in the Dynamic Island: the next set, and the rest countdown or the
/// time trained. A tap opens the workout.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkout(context: context).widgetURL(workoutURL)
        } dynamicIsland: { context in
            let workout = WorkoutMoment(context)
            let tint = Color(hex: context.attributes.restDark)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "dumbbell.fill").font(.title3).foregroundStyle(workout.inRest ? tint : Color.secondary).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutClock(workout: workout, tint: tint, size: 24).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        WorkoutLines(context: context, workout: workout, tint: tint, clock: false)
                        RestProgress(workout: workout, tint: tint)
                    }.padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(workout.inRest ? tint : Color.secondary)
            } compactTrailing: {
                if let rest = workout.resting {
                    Text(timerInterval: rest, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 44).foregroundStyle(tint)
                } else if workout.restDone {
                    Text("Go").fontWeight(.semibold).foregroundStyle(tint)
                } else {
                    Text("\(context.state.completed)/\(context.state.total)").monospacedDigit()
                }
            } minimal: {
                if let rest = workout.resting {
                    ProgressView(timerInterval: rest, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular).tint(tint)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(workout.inRest ? tint : Color.secondary)
                }
            }
            .widgetURL(workoutURL).keylineTint(tint)
        }
    }
    private var workoutURL: URL? { URL(string: "setform://workout") }
}

/// Where the workout stands when the activity is drawn.
struct WorkoutMoment {
    /// The rest still running.
    var resting: ClosedRange<Date>?
    /// A rest that has run out and is waiting for the next set.
    var restDone = false
    var pausedAfter: TimeInterval?
    var clockStart: Date
    /// Resting or just finished resting, when the icon takes the Rest color.
    var inRest: Bool { resting != nil || restDone }

    init(_ context: ActivityViewContext<WorkoutActivityAttributes>) {
        let state = context.state
        clockStart = state.clockStart; pausedAfter = state.pausedAfter
        guard pausedAfter == nil, let end = state.restEnd else { return }
        // The content goes stale at the end of the rest, which is what redraws it without the app.
        if !context.isStale, end > Date() { resting = min(state.restStart ?? end, end.addingTimeInterval(-1))...end }
        else { restDone = true }
    }

    func label(_ state: WorkoutActivityAttributes.ContentState) -> String {
        if resting != nil { return "Rest" }
        if pausedAfter != nil { return "Paused" }
        return "\(state.completed) of \(state.total) sets"
    }
}

/// The rest countdown, "Rest done", or the time trained.
struct WorkoutClock: View {
    let workout: WorkoutMoment
    let tint: Color
    let size: CGFloat
    var body: some View {
        Group {
            // A running timer asks for all the width it is offered, so each is held to what its digits need.
            if let rest = workout.resting {
                Text(timerInterval: rest, countsDown: true).foregroundStyle(tint).multilineTextAlignment(.trailing)
                    .frame(maxWidth: size * (rest.upperBound.timeIntervalSince(rest.lowerBound) >= 3600 ? 4.2 : 3), alignment: .trailing)
            } else if workout.restDone {
                Text("Rest done").foregroundStyle(tint).fixedSize()
            } else if let paused = workout.pausedAfter {
                Text(Duration.seconds(paused).formatted(.time(pattern: paused >= 3600 ? .hourMinuteSecond : .minuteSecond))).fixedSize()
            } else {
                Text(timerInterval: workout.clockStart...max(workout.clockStart, Date()).addingTimeInterval(86_400), countsDown: false)
                    .multilineTextAlignment(.trailing).frame(maxWidth: size * 4.2, alignment: .trailing)
            }
        }
        .font(.system(size: size, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The next exercise over its next set, with what the clock is counting at the trailing edge.
struct WorkoutLines: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    let workout: WorkoutMoment
    let tint: Color
    /// The Lock Screen carries the clock on the first line; the Dynamic Island shows it above.
    let clock: Bool
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(context.state.exercise ?? context.attributes.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if clock { WorkoutClock(workout: workout, tint: tint, size: 28) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(context.state.detail ?? "All sets logged").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(workout.label(context.state)).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }.monospacedDigit()
        }
    }
}

/// How much of the rest is left, as a bar that empties. Hidden between rests.
struct RestProgress: View {
    let workout: WorkoutMoment
    let tint: Color
    var body: some View {
        if let rest = workout.resting {
            ProgressView(timerInterval: rest, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear).tint(tint)
        }
    }
}

struct LockScreenWorkout: View {
    @Environment(\.colorScheme) private var scheme
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var body: some View {
        let workout = WorkoutMoment(context)
        let tint = Color(hex: scheme == .dark ? context.attributes.restDark : context.attributes.restLight)
        VStack(spacing: 10) {
            WorkoutLines(context: context, workout: workout, tint: tint, clock: true)
            RestProgress(workout: workout, tint: tint)
        }.padding(16)
    }
}

private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
