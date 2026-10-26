import Foundation

/// An exercise's heaviest completed working set in one session.
public struct TopSet: Equatable, Sendable {
    public var sessionID: UUID
    public var date: Date
    public var weight: Double
    public var reps: Int
}

/// The heaviest weight lifted for at least `reps` reps, and when.
public struct RepRecord: Equatable, Sendable {
    public var reps: Int
    public var weight: Double
    public var date: Date
}

/// Training volume in one week or month, starting at `start`.
public struct VolumeBucket: Equatable, Sendable {
    public var start: Date
    public var volume: Double
}

/// Body weight smoothed over the seven days up to each weigh-in.
public struct BodyWeightTrend: Equatable, Sendable {
    public var date: Date
    public var average: Double
}

public extension TrainingData {
    /// Each session's heaviest completed working set with a logged weight and reps, oldest first.
    func topSets(exerciseID: UUID, variantID: UUID? = nil, since: Date = .distantPast) -> [TopSet] {
        sessions.filter { $0.startedAt >= since }.sorted { $0.startedAt < $1.startedAt }.compactMap { session in
            session.exercises.filter { $0.exerciseID == exerciseID && (variantID == nil || $0.variantID == variantID) }
                .flatMap(\.sets)
                .compactMap { set -> TopSet? in
                    guard set.completedAt != nil, set.plan.kind != .warmup, let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { return nil }
                    return TopSet(sessionID: session.id, date: session.startedAt, weight: weight, reps: reps)
                }
                .max { $0.weight == $1.weight ? $0.reps < $1.reps : $0.weight < $1.weight }
        }
    }

    /// Deloads and light days: sessions whose top set is under `threshold` of the heaviest of the three
    /// regular sessions before them. They stay on the chart but off its trend line and out of its statistics.
    static func lightSessions(_ tops: [TopSet], threshold: Double = 0.85) -> Set<UUID> {
        var light: Set<UUID> = []
        var recent: [Double] = []
        for top in tops {
            if let reference = recent.suffix(3).max(), top.weight < reference * threshold { light.insert(top.sessionID); continue }
            recent.append(top.weight)
        }
        return light
    }

    /// For each rep count up to the most reps logged, the heaviest weight lifted for at least that many reps.
    /// A count is left out when a higher one matches its weight: 190 × 8 already says 190 for 5.
    func repRecords(exerciseID: UUID, variantID: UUID? = nil, counts: [Int] = [1, 3, 5, 8, 10, 12]) -> [RepRecord] {
        let sets = sessions.flatMap { session in
            session.exercises.filter { $0.exerciseID == exerciseID && (variantID == nil || $0.variantID == variantID) }.flatMap(\.sets)
                .compactMap { set -> (weight: Double, reps: Int, date: Date)? in
                    guard set.completedAt != nil, set.plan.kind != .warmup, let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { return nil }
                    return (weight, reps, session.startedAt)
                }
        }
        let records = counts.compactMap { count in
            sets.filter { $0.reps >= count }
                .max { $0.weight == $1.weight ? $0.date > $1.date : $0.weight < $1.weight }
                .map { RepRecord(reps: count, weight: $0.weight, date: $0.date) }
        }
        return records.enumerated().filter { index, record in index + 1 == records.count || records[index + 1].weight < record.weight }.map(\.element)
    }

    /// Working-set volume per week (or month), credited to primary muscles like `muscleSummary`. Empty
    /// weeks are kept so gaps show. `muscle` limits it to one primary muscle.
    func volumeBuckets(programID: UUID? = nil, since: Date, until: Date = .now, muscle: String? = nil, monthly: Bool, calendar: Calendar = .current) -> [VolumeBucket] {
        let first = since == .distantPast ? sessions(inProgram: programID).map(\.startedAt).min() ?? until : since
        let unit: Calendar.Component = monthly ? .month : .weekOfYear
        guard var start = calendar.dateInterval(of: unit, for: first)?.start else { return [] }
        var buckets: [VolumeBucket] = []
        while start < until, buckets.count < 520 {
            guard let end = calendar.date(byAdding: unit, value: 1, to: start) else { break }
            let summary = muscleSummary(programID: programID, since: max(start, since), until: min(end, until))
            let volume = muscle.map { name in summary.first { $0.name == name }?.volume ?? 0 } ?? summary.reduce(0) { $0 + $1.volume }
            buckets.append(VolumeBucket(start: start, volume: volume))
            start = end
        }
        return buckets
    }

    /// Cardio time in seconds, or distance in meters, per week (or month), from completed sets of cardio
    /// exercises. Empty periods are kept so gaps show. `exerciseID` limits it to one exercise.
    func cardioBuckets(programID: UUID? = nil, since: Date, until: Date = .now, exerciseID: UUID? = nil, distance: Bool, monthly: Bool, calendar: Calendar = .current) -> [VolumeBucket] {
        let cardio = sessions(inProgram: programID).filter { $0.skipped != true }.map { session in
            (date: session.startedAt, amount: session.exercises.filter { $0.mode == .cardio && (exerciseID == nil || $0.exerciseID == exerciseID) }
                .flatMap(\.sets).filter { $0.completedAt != nil && $0.plan.kind != .warmup }
                .reduce(0.0) { $0 + ((distance ? $1.meters : $1.seconds) ?? 0) })
        }.filter { $0.amount > 0 }
        let first = since == .distantPast ? cardio.map(\.date).min() ?? until : since
        let unit: Calendar.Component = monthly ? .month : .weekOfYear
        guard var start = calendar.dateInterval(of: unit, for: first)?.start else { return [] }
        var buckets: [VolumeBucket] = []
        while start < until, buckets.count < 520 {
            guard let end = calendar.date(byAdding: unit, value: 1, to: start) else { break }
            let amount = cardio.filter { $0.date >= max(start, since) && $0.date < min(end, until) }.reduce(0) { $0 + $1.amount }
            buckets.append(VolumeBucket(start: start, volume: amount))
            start = end
        }
        return buckets
    }

    /// The seven-day average at each weigh-in from `since`, so one heavy morning doesn't swing the trend.
    func bodyWeightTrend(since: Date = .distantPast) -> [BodyWeightTrend] {
        let entries = bodyWeights.sorted { $0.date < $1.date }
        return entries.filter { $0.date >= since }.map { entry in
            let window = entries.filter { $0.date <= entry.date && $0.date > entry.date.addingTimeInterval(-7 * 86_400) }
            return BodyWeightTrend(date: entry.date, average: window.map(\.kilograms).reduce(0, +) / Double(window.count))
        }
    }
}
