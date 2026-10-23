import Foundation

/// Active energy recorded during part of a workout, such as one of an Apple Watch's per-minute samples.
public struct HealthSegment: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var kcal: Double
    public init(start: Date, end: Date, kcal: Double) { self.start = start; self.end = end; self.kcal = kcal }
}

/// A workout in Apple Health, as Lifting reads it. Workouts from other apps and devices
/// (an Apple Watch, for example) are only ever read; Lifting can delete only the copies it saved itself.
public struct HealthWorkout: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var sourceName: String
    /// Saved by Lifting.
    public var isOwn: Bool
    /// For a workout Lifting saved, the session it copies.
    public var sessionID: UUID?
    public var activityName: String
    public var activeKcal: Double?
    public var averageHeartRate: Double?
    /// When the energy was burned, read only for a workout that spans more than one session.
    public var energySegments: [HealthSegment]?
    public init(id: UUID = UUID(), start: Date, end: Date, sourceName: String, isOwn: Bool = false, sessionID: UUID? = nil, activityName: String = "Workout", activeKcal: Double? = nil, averageHeartRate: Double? = nil, energySegments: [HealthSegment]? = nil) {
        self.id = id; self.start = start; self.end = end; self.sourceName = sourceName; self.isOwn = isOwn; self.sessionID = sessionID
        self.activityName = activityName; self.activeKcal = activeKcal; self.averageHeartRate = averageHeartRate; self.energySegments = energySegments
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    var hasData: Bool { activeKcal != nil || averageHeartRate != nil }
}

/// One Apple Health workout's share of a session, for example a watch strength workout and a run.
public struct HealthPart: Codable, Equatable, Sendable {
    public var workoutID: UUID
    public var activityName: String
    public var sourceName: String
    public var start: Date
    /// Time of the workout counted toward this session; less than the whole workout when it spans two sessions.
    public var duration: TimeInterval
    public var activeKcal: Double?
    public init(workoutID: UUID, activityName: String, sourceName: String, start: Date, duration: TimeInterval, activeKcal: Double?) {
        self.workoutID = workoutID; self.activityName = activityName; self.sourceName = sourceName; self.start = start; self.duration = duration; self.activeKcal = activeKcal
    }
    var isValid: Bool {
        activityName.count <= 100 && sourceName.count <= 200 && duration.isFinite && duration >= 0
            && (activeKcal.map { $0.isFinite && (0...100_000).contains($0) } ?? true)
    }
}

/// Calories and heart rate a session took from the Apple Health workouts recorded at the same time.
/// The values stay in Lifting's log even if Health later stops sharing them.
public struct HealthLink: Codable, Equatable, Sendable {
    public var workoutIDs: [UUID] = []
    public var sourceName: String = ""
    public var activeKcal: Double?
    public var averageHeartRate: Double?
    /// Each workout that contributed, in time order.
    public var parts: [HealthPart]?
    /// Workouts Lifting saved to Apple Health for this session, covering only time nothing else recorded.
    public var savedWorkoutIDs: [UUID]?
    /// The person removed the match, so Lifting does not link this session again.
    public var unlinked: Bool?
    public init(workoutIDs: [UUID] = [], sourceName: String = "", activeKcal: Double? = nil, averageHeartRate: Double? = nil, parts: [HealthPart]? = nil, savedWorkoutIDs: [UUID]? = nil, unlinked: Bool? = nil) {
        self.workoutIDs = workoutIDs; self.sourceName = sourceName; self.activeKcal = activeKcal; self.averageHeartRate = averageHeartRate
        self.parts = parts; self.savedWorkoutIDs = savedWorkoutIDs; self.unlinked = unlinked
    }
    public var hasData: Bool { activeKcal != nil || averageHeartRate != nil }
    var isValid: Bool {
        workoutIDs.count <= 50 && sourceName.count <= 200 && (parts ?? []).count <= 50 && (parts ?? []).allSatisfy(\.isValid)
            && (savedWorkoutIDs ?? []).count <= 50
            && (activeKcal.map { $0.isFinite && (0...100_000).contains($0) } ?? true)
            && (averageHeartRate.map { $0.isFinite && (20...300).contains($0) } ?? true)
    }
    mutating func clearValues() { workoutIDs = []; sourceName = ""; activeKcal = nil; averageHeartRate = nil; parts = nil }
}

/// Apple Health choices for this device. Health access is granted per device, so these do not sync.
public struct HealthSettings: Codable, Equatable, Sendable {
    public var read = false
    public var write = false
    /// Saving starts with sessions that end after this, so turning it on never copies old history.
    public var writeSince: Date?
    public init(read: Bool = false, write: Bool = false, writeSince: Date? = nil) { self.read = read; self.write = write; self.writeSince = writeSince }
}

/// The activity type of a workout Lifting saves.
public enum HealthActivity: String, Equatable, Sendable {
    case strength, running, walking, cycling, rowing, stairs, elliptical, swimming, mixedCardio
    /// The closest activity for a cardio exercise, from its name.
    public static func cardio(named name: String) -> HealthActivity {
        let text = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("run", "sprint", "jog") { return .running }
        if has("walk", "hike") { return .walking }
        if has("bike", "cycl", "spin") { return .cycling }
        if has("row") { return .rowing }
        if has("stair", "step") { return .stairs }
        if has("ellip") { return .elliptical }
        if has("swim") { return .swimming }
        return .mixedCardio
    }
}

/// A workout Lifting should save: part or all of a session's time that no other source recorded.
public struct HealthSave: Equatable, Sendable {
    public var sessionID: UUID
    public var start: Date
    public var end: Date
    public var activity: HealthActivity
    public init(sessionID: UUID, start: Date, end: Date, activity: HealthActivity) { self.sessionID = sessionID; self.start = start; self.end = end; self.activity = activity }
}

/// What to change in Apple Health after reconciling: only Lifting's own workouts are ever deleted.
public struct HealthPlan: Equatable, Sendable {
    public var deletions: [UUID] = []
    public var saves: [HealthSave] = []
    public init(deletions: [UUID] = [], saves: [HealthSave] = []) { self.deletions = deletions; self.saves = saves }
}

public enum HealthMatching {
    /// A watch workout often starts a few minutes before the first set and ends after Finish.
    public static let margin: TimeInterval = 10 * 60
    /// Watch workouts can take a few minutes to reach the phone, so Lifting waits before saving its own.
    public static let saveDelay: TimeInterval = 10 * 60
    /// How far back Lifting looks for workouts to match.
    public static let lookback: TimeInterval = 60 * 86_400
    /// Time left over beside another source's workout shorter than this is not saved on its own.
    public static let shortestFill: TimeInterval = 5 * 60
    /// Lifting's own workout may touch another source's by up to this much before it counts as a repeat.
    static let tolerance: TimeInterval = 60

    static func overlap(_ a: (Date, Date), _ b: (Date, Date)) -> TimeInterval {
        max(0, min(a.1, b.1).timeIntervalSince(max(a.0, b.0)))
    }
    /// A workout from another source belongs to a session when at least half of it falls within the session, give or take the margin.
    public static func belongs(_ workout: HealthWorkout, to session: Session) -> Bool {
        guard let end = session.endedAt, workout.duration > 0 else { return false }
        let window = (session.startedAt.addingTimeInterval(-margin), end.addingTimeInterval(margin))
        return overlap((workout.start, workout.end), window) >= 0.5 * workout.duration
    }

    /// How much of each workout counts toward each session. A workout near one session counts toward it in full.
    /// A workout near several (one watch workout kept running across two sessions) is split by when its time and
    /// energy fall, so no calorie counts twice.
    static func shares(of workouts: [HealthWorkout], among sessions: [Session]) -> [UUID: [HealthPart]] {
        var result: [UUID: [HealthPart]] = [:]
        for workout in workouts where workout.hasData {
            let candidates = sessions.filter { belongs(workout, to: $0) }
            guard !candidates.isEmpty else { continue }
            if candidates.count == 1 {
                result[candidates[0].id, default: []].append(HealthPart(workoutID: workout.id, activityName: workout.activityName, sourceName: workout.sourceName, start: workout.start, duration: workout.duration, activeKcal: workout.activeKcal))
                continue
            }
            func nearest(_ moment: Date) -> UUID {
                candidates.min { a, b in distance(moment, a) < distance(moment, b) }!.id
            }
            var seconds: [UUID: TimeInterval] = [:], first: [UUID: Date] = [:], kcal: [UUID: Double] = [:]
            var cursor = workout.start
            while cursor < workout.end {
                let next = min(workout.end, cursor.addingTimeInterval(60))
                let owner = nearest(cursor.addingTimeInterval(next.timeIntervalSince(cursor) / 2))
                seconds[owner, default: 0] += next.timeIntervalSince(cursor)
                first[owner] = first[owner] ?? cursor
                cursor = next
            }
            if let total = workout.activeKcal {
                let segments = (workout.energySegments ?? []).filter { $0.kcal.isFinite && $0.kcal >= 0 && $0.end >= $0.start }
                let sum = segments.reduce(0) { $0 + $1.kcal }
                if sum > 0 {
                    for segment in segments {
                        let middle = segment.start.addingTimeInterval(segment.end.timeIntervalSince(segment.start) / 2)
                        kcal[nearest(middle), default: 0] += segment.kcal * total / sum
                    }
                } else {
                    for (id, time) in seconds { kcal[id] = total * time / workout.duration }
                }
            }
            for session in candidates {
                let time = seconds[session.id] ?? 0
                let energy = kcal[session.id]
                guard time > 0 || (energy ?? 0) > 0 else { continue }
                result[session.id, default: []].append(HealthPart(workoutID: workout.id, activityName: workout.activityName, sourceName: workout.sourceName, start: first[session.id] ?? workout.start, duration: time, activeKcal: workout.activeKcal == nil ? nil : energy ?? 0))
            }
        }
        return result
    }
    static func distance(_ moment: Date, _ session: Session) -> TimeInterval {
        let end = session.endedAt ?? session.startedAt
        return max(0, session.startedAt.timeIntervalSince(moment), moment.timeIntervalSince(end))
    }

    /// The parts of `interval` that none of `covered` overlaps. With nothing covering it, the whole interval;
    /// otherwise only pieces long enough to stand as a workout.
    static func uncovered(_ interval: (Date, Date), by covered: [(Date, Date)]) -> [(Date, Date)] {
        let clipped = covered.map { (max($0.0, interval.0), min($0.1, interval.1)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard !clipped.isEmpty else { return interval.1 > interval.0 ? [interval] : [] }
        var gaps: [(Date, Date)] = [], cursor = interval.0
        for piece in clipped {
            if piece.0 > cursor { gaps.append((cursor, piece.0)) }
            cursor = max(cursor, piece.1)
        }
        if interval.1 > cursor { gaps.append((cursor, interval.1)) }
        return gaps.filter { $0.1.timeIntervalSince($0.0) >= shortestFill }
    }
}

public extension TrainingData {
    /// Sessions that Apple Health workouts can attach to: finished, not skipped, and recent.
    func healthEligible(_ session: Session, now: Date) -> Bool {
        session.endedAt != nil && session.skipped != true && session.startedAt >= now.addingTimeInterval(-HealthMatching.lookback)
    }

    /// The time span to read from Apple Health, or nil when no session can use it.
    func healthRange(now: Date) -> DateInterval? {
        guard let earliest = sessions.filter({ healthEligible($0, now: now) }).map(\.startedAt).min() else { return nil }
        let start = earliest.addingTimeInterval(-HealthMatching.margin)
        return start < now ? DateInterval(start: start, end: now) : nil
    }

    /// The windows around recent sessions where Apple Health workouts can match.
    func healthWindows(now: Date) -> [DateInterval] {
        sessions.filter { healthEligible($0, now: now) }.compactMap { session in
            session.endedAt.map { DateInterval(start: session.startedAt.addingTimeInterval(-HealthMatching.margin), end: $0.addingTimeInterval(HealthMatching.margin)) }
        }
    }

    /// Updates sessions from the Apple Health workouts in `healthRange` and returns what Lifting should
    /// change there. Workouts from other sources are never changed. Lifting's own workouts cover only time no
    /// other source recorded; one that overlaps another source's workout is removed and, when saving is on,
    /// replaced with the time still uncovered.
    mutating func reconcileHealth(_ workouts: [HealthWorkout], now: Date = Date(), saveDelay: TimeInterval = HealthMatching.saveDelay) -> HealthPlan {
        var plan = HealthPlan()
        let others = workouts.filter { !$0.isOwn }
        let own = workouts.filter(\.isOwn)
        let health = settings.health ?? HealthSettings()
        let eligible = sessions.filter { healthEligible($0, now: now) }
        let shares = HealthMatching.shares(of: others, among: eligible)
        func repeats(_ copy: HealthWorkout) -> Bool {
            others.contains { HealthMatching.overlap((copy.start, copy.end), ($0.start, $0.end)) > HealthMatching.tolerance }
        }
        var handled = Set<UUID>()
        for index in sessions.indices where healthEligible(sessions[index], now: now) {
            let session = sessions[index]
            guard let end = session.endedAt else { continue }
            var link = session.health ?? HealthLink()
            let parts = (shares[session.id] ?? []).sorted { $0.start < $1.start }
            let visible = Set(others.map(\.id))
            // Workouts this session linked that now belong elsewhere no longer count here.
            // Values are kept only when the linked workouts are gone from Health, for example after access is turned off.
            let lost = !link.workoutIDs.isEmpty && link.workoutIDs.allSatisfy { !visible.contains($0) }
            if parts.isEmpty, !lost { link.clearValues() }
            if link.unlinked != true, !parts.isEmpty {
                link.workoutIDs = parts.map(\.workoutID)
                link.sourceName = parts.max { $0.duration < $1.duration }?.sourceName ?? ""
                let calories = parts.compactMap(\.activeKcal)
                link.activeKcal = calories.isEmpty ? nil : calories.reduce(0, +)
                let rates = Dictionary(others.compactMap { workout in workout.averageHeartRate.map { (workout.id, $0) } }, uniquingKeysWith: { first, _ in first })
                let rated = parts.filter { rates[$0.workoutID] != nil && $0.duration > 0 }
                let time = rated.reduce(0) { $0 + $1.duration }
                link.averageHeartRate = time > 0 ? rated.reduce(0) { $0 + rates[$1.workoutID]! * $1.duration } / time : nil
                link.parts = parts
            }
            if link.unlinked == true { link.clearValues() }
            // Lifting's own workouts for this session.
            let copies = own.filter { $0.sessionID == session.id }
            handled.formUnion(copies.map(\.id))
            let canSave = health.write && session.completedSets > 0 && !lost
                && (health.writeSince.map { end >= $0 } ?? false) && end <= now.addingTimeInterval(-saveDelay)
            var kept: [UUID] = []
            if canSave {
                let gaps = HealthMatching.uncovered((session.startedAt, end), by: others.map { ($0.start, $0.end) } + (session.pauses ?? []).map { ($0.start, $0.end) })
                for copy in copies {
                    if gaps.contains(where: { abs($0.0.timeIntervalSince(copy.start)) <= HealthMatching.tolerance && abs($0.1.timeIntervalSince(copy.end)) <= HealthMatching.tolerance }) { kept.append(copy.id) }
                    else { plan.deletions.append(copy.id) }
                }
                for gap in gaps where !copies.contains(where: { kept.contains($0.id) && abs(gap.0.timeIntervalSince($0.start)) <= HealthMatching.tolerance && abs(gap.1.timeIntervalSince($0.end)) <= HealthMatching.tolerance }) {
                    plan.saves.append(HealthSave(sessionID: session.id, start: gap.0, end: gap.1, activity: activity(for: session, from: gap.0, to: gap.1)))
                }
            } else {
                for copy in copies { if repeats(copy) { plan.deletions.append(copy.id) } else { kept.append(copy.id) } }
            }
            link.savedWorkoutIDs = kept.isEmpty ? nil : kept
            sessions[index].health = link == HealthLink() ? nil : link
        }
        // Copies whose session is gone or too old to save again are removed only where they repeat another recording.
        for copy in own where !handled.contains(copy.id) && repeats(copy) { plan.deletions.append(copy.id) }
        return plan
    }

    /// The activity for time Lifting saves: the cardio exercise done then, or strength training.
    func activity(for session: Session, from start: Date, to end: Date) -> HealthActivity {
        let done = session.exercises.filter { $0.sets.contains { $0.completedAt != nil } }
        let during = done.filter { item in item.sets.contains { set in set.completedAt.map { $0 >= start.addingTimeInterval(-HealthMatching.tolerance) && $0 <= end.addingTimeInterval(HealthMatching.tolerance) } ?? false } }
        let pool = during.isEmpty ? done : during
        guard !pool.isEmpty, pool.allSatisfy({ $0.mode == .cardio }) else { return .strength }
        let main = pool.max { a, b in a.sets.filter { $0.completedAt != nil }.count < b.sets.filter { $0.completedAt != nil }.count }!
        return HealthActivity.cardio(named: main.name)
    }

    /// Notes a workout Lifting saved to Apple Health for a session.
    mutating func recordSavedHealthWorkout(_ workoutID: UUID, for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var link = sessions[index].health ?? HealthLink()
        link.savedWorkoutIDs = (link.savedWorkoutIDs ?? []) + [workoutID]
        sessions[index].health = link
    }

    /// Removes a session's Apple Health match and stops future matching for it.
    mutating func unlinkHealth(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].health = HealthLink(savedWorkoutIDs: sessions[index].health?.savedWorkoutIDs, unlinked: true)
    }

    /// Lets a session match Apple Health workouts again after it was unlinked.
    mutating func relinkHealth(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), var link = sessions[index].health else { return }
        link.unlinked = nil
        sessions[index].health = link == HealthLink() ? nil : link
    }

    /// The library without values read from Apple Health. Copies written to a shared folder, which may be
    /// iCloud Drive, leave health data out; each device reads it from Apple Health itself.
    var withoutHealthData: TrainingData {
        var copy = self
        for index in copy.sessions.indices { copy.sessions[index].health = nil }
        return copy
    }
}
