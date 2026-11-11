import Foundation

/// A lift's heaviest set in a workout that beat every earlier set of that lift.
public struct RecordSet: Equatable, Identifiable, Sendable {
    public var exerciseID: UUID
    public var setID: UUID
    public var name: String
    public var weight: Double
    public var reps: Int
    /// The best before this workout.
    public var previousWeight: Double
    public var previousReps: Int
    public var id: UUID { setID }
}

/// The set to do next in a workout, and where it falls among the exercise's sets of its kind.
public struct NextSet: Equatable, Sendable {
    public var exercise: SessionExercise
    public var set: LoggedSet
    public var number: Int
    public var count: Int
}

public extension LoggedSet {
    /// A completed working set with a weight and reps, the kind that can be a best.
    var lifted: (weight: Double, reps: Int)? {
        guard completedAt != nil, plan.kind != .warmup, let weight, weight > 0, let reps, reps > 0 else { return nil }
        return (weight, reps)
    }
}

public extension Session {
    /// The name of a workout started without a day. Such workouts share nothing but the name.
    static let unplannedName = "Workout"

    /// The set to do next: in the open exercise, else the first exercise with a set left, the first unlogged
    /// set after the last logged one, so skipped warm-ups are not offered again. Warm-ups count among
    /// warm-ups and the rest among the rest: "Warm-up 1 of 2", "Set 3 of 4".
    var nextSet: NextSet? {
        func pending(_ item: SessionExercise) -> Bool { item.sets.contains { $0.completedAt == nil } }
        guard let item = exercises.first(where: { $0.collapsed == false && pending($0) }) ?? exercises.first(where: pending) else { return nil }
        let logged = item.sets.lastIndex { $0.completedAt != nil } ?? -1
        guard let index = item.sets.indices.first(where: { $0 > logged && item.sets[$0].completedAt == nil })
                ?? item.sets.firstIndex(where: { $0.completedAt == nil }) else { return nil }
        let warmup = item.sets[index].plan.kind == .warmup
        let alike = item.sets.indices.filter { (item.sets[$0].plan.kind == .warmup) == warmup }
        return NextSet(exercise: item, set: item.sets[index], number: (alike.firstIndex(of: index) ?? 0) + 1, count: alike.count)
    }
}

public extension TrainingData {
    /// The workout before this one on the same day: the same saved day, or the same name when it has no day.
    func previousSession(before session: Session) -> Session? {
        guard session.skipped != true, session.routineID != nil || session.name != Session.unplannedName else { return nil }
        return sessions.filter {
            $0.id != session.id && $0.skipped != true && $0.startedAt < session.startedAt
                && $0.routineID == session.routineID && (session.routineID != nil || $0.name == session.name)
        }.max { $0.startedAt < $1.startedAt }
    }

    /// Lifts whose heaviest set in this workout beat every earlier set of that lift, more reps breaking a tie,
    /// in workout order. A lift done for the first time has nothing to beat.
    func records(in session: Session) -> [RecordSet] {
        guard session.skipped != true else { return [] }
        func beats(_ a: (weight: Double, reps: Int), _ b: (weight: Double, reps: Int)) -> Bool { a.weight > b.weight || (a.weight == b.weight && a.reps > b.reps) }
        var tops: [(item: SessionExercise, set: LoggedSet)] = []
        for item in session.exercises where item.mode == .strength {
            for set in item.sets {
                guard let lift = set.lifted else { continue }
                if let held = tops.firstIndex(where: { $0.item.exerciseID == item.exerciseID }) {
                    if let top = tops[held].set.lifted, beats(lift, top) { tops[held] = (item, set) }
                } else { tops.append((item, set)) }
            }
        }
        var earlier: [UUID: (weight: Double, reps: Int)] = [:]
        let wanted = Set(tops.map(\.item.exerciseID))
        for other in sessions where other.id != session.id && other.skipped != true && other.startedAt < session.startedAt {
            for item in other.exercises where item.mode == .strength && wanted.contains(item.exerciseID) {
                for set in item.sets {
                    guard let lift = set.lifted else { continue }
                    if let held = earlier[item.exerciseID], !beats(lift, held) { continue }
                    earlier[item.exerciseID] = lift
                }
            }
        }
        return tops.compactMap { top in
            guard let lift = top.set.lifted, let before = earlier[top.item.exerciseID], beats(lift, before) else { return nil }
            return RecordSet(exerciseID: top.item.exerciseID, setID: top.set.id, name: top.item.name, weight: lift.weight, reps: lift.reps,
                             previousWeight: before.weight, previousReps: before.reps)
        }
    }
}
