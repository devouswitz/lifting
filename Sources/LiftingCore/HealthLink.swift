import Foundation

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
    public init(id: UUID = UUID(), start: Date, end: Date, sourceName: String, isOwn: Bool = false, sessionID: UUID? = nil, activityName: String = "Workout", activeKcal: Double? = nil, averageHeartRate: Double? = nil) {
        self.id = id; self.start = start; self.end = end; self.sourceName = sourceName; self.isOwn = isOwn; self.sessionID = sessionID
        self.activityName = activityName; self.activeKcal = activeKcal; self.averageHeartRate = averageHeartRate
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    var hasData: Bool { activeKcal != nil || averageHeartRate != nil }
}

/// Calories and heart rate a session took from the Apple Health workouts recorded at the same time.
/// The values stay in Lifting's log even if Health later stops sharing them.
public struct HealthLink: Codable, Equatable, Sendable {
    public var workoutIDs: [UUID] = []
    public var sourceName: String = ""
    public var activeKcal: Double?
    public var averageHeartRate: Double?
    /// The workout Lifting saved to Apple Health for this session, when nothing else recorded that time.
    public var savedWorkoutID: UUID?
    /// The person removed the match, so Lifting does not link this session again.
    public var unlinked: Bool?
    public init(workoutIDs: [UUID] = [], sourceName: String = "", activeKcal: Double? = nil, averageHeartRate: Double? = nil, savedWorkoutID: UUID? = nil, unlinked: Bool? = nil) {
        self.workoutIDs = workoutIDs; self.sourceName = sourceName; self.activeKcal = activeKcal; self.averageHeartRate = averageHeartRate
        self.savedWorkoutID = savedWorkoutID; self.unlinked = unlinked
    }
    public var hasData: Bool { activeKcal != nil || averageHeartRate != nil }
    var isValid: Bool {
        workoutIDs.count <= 50 && sourceName.count <= 200
            && (activeKcal.map { $0.isFinite && (0...100_000).contains($0) } ?? true)
            && (averageHeartRate.map { $0.isFinite && (20...300).contains($0) } ?? true)
    }
}

/// Apple Health choices for this device. Health access is granted per device, so these do not sync.
public struct HealthSettings: Codable, Equatable, Sendable {
    public var read = false
    public var write = false
    /// Saving starts with sessions that end after this, so turning it on never copies old history.
    public var writeSince: Date?
    public init(read: Bool = false, write: Bool = false, writeSince: Date? = nil) { self.read = read; self.write = write; self.writeSince = writeSince }
}

/// What to change in Apple Health after reconciling: only Lifting's own workouts are ever deleted.
public struct HealthPlan: Equatable, Sendable {
    public var deletions: [UUID] = []
    public var saves: [UUID] = []
    public init(deletions: [UUID] = [], saves: [UUID] = []) { self.deletions = deletions; self.saves = saves }
}

public enum HealthMatching {
    /// A watch workout often starts a few minutes before the first set and ends after Finish.
    public static let margin: TimeInterval = 10 * 60
    /// Watch workouts can take a few minutes to reach the phone, so Lifting waits before saving its own.
    public static let saveDelay: TimeInterval = 10 * 60
    /// How far back Lifting looks for workouts to match.
    public static let lookback: TimeInterval = 60 * 86_400

    static func overlap(_ a: (Date, Date), _ b: (Date, Date)) -> TimeInterval {
        max(0, min(a.1, b.1).timeIntervalSince(max(a.0, b.0)))
    }
    /// A workout from another source belongs to a session when at least half of it falls within the session, give or take the margin.
    public static func belongs(_ workout: HealthWorkout, to session: Session) -> Bool {
        guard let end = session.endedAt, workout.duration > 0 else { return false }
        let window = (session.startedAt.addingTimeInterval(-margin), end.addingTimeInterval(margin))
        return overlap((workout.start, workout.end), window) >= 0.5 * workout.duration
    }
    /// Two recordings of the same time: they overlap by at least half of the shorter one.
    public static func sameTime(_ a: (Date, Date), _ b: (Date, Date)) -> Bool {
        let shorter = min(a.1.timeIntervalSince(a.0), b.1.timeIntervalSince(b.0))
        return shorter > 0 && overlap(a, b) >= 0.5 * shorter
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

    /// Updates sessions from the Apple Health workouts in `healthRange` and returns what Lifting should
    /// change there. Workouts from other sources are never changed. Lifting deletes its own copy when another
    /// source recorded the same time, and saves a copy only when nothing else did.
    mutating func reconcileHealth(_ workouts: [HealthWorkout], now: Date = Date(), saveDelay: TimeInterval = HealthMatching.saveDelay) -> HealthPlan {
        var plan = HealthPlan()
        let others = workouts.filter { !$0.isOwn }
        let own = workouts.filter(\.isOwn)
        for copy in own where others.contains(where: { HealthMatching.sameTime((copy.start, copy.end), ($0.start, $0.end)) }) {
            plan.deletions.append(copy.id)
        }
        let health = settings.health ?? HealthSettings()
        for index in sessions.indices where healthEligible(sessions[index], now: now) {
            let session = sessions[index]
            guard let end = session.endedAt else { continue }
            var link = session.health ?? HealthLink()
            let matched = others.filter { HealthMatching.belongs($0, to: session) }
            let copy = own.first { $0.sessionID == session.id && !plan.deletions.contains($0.id) }
            link.savedWorkoutID = copy?.id
            let recorded = matched.filter(\.hasData)
            if link.unlinked != true, !recorded.isEmpty {
                link.workoutIDs = recorded.map(\.id)
                link.sourceName = recorded.max { $0.duration < $1.duration }?.sourceName ?? ""
                let calories = recorded.compactMap(\.activeKcal)
                link.activeKcal = calories.isEmpty ? nil : calories.reduce(0, +)
                let rates = recorded.filter { $0.averageHeartRate != nil && $0.duration > 0 }
                let time = rates.reduce(0) { $0 + $1.duration }
                link.averageHeartRate = time > 0 ? rates.reduce(0) { $0 + $1.averageHeartRate! * $1.duration } / time : nil
            }
            let alreadyRecorded = !matched.isEmpty || !link.workoutIDs.isEmpty || link.hasData
                || others.contains { HealthMatching.sameTime(($0.start, $0.end), (session.startedAt, end)) }
            if health.write, copy == nil, !alreadyRecorded, session.completedSets > 0,
               let since = health.writeSince, end >= since, end <= now.addingTimeInterval(-saveDelay) {
                plan.saves.append(session.id)
            }
            sessions[index].health = link == HealthLink() ? nil : link
        }
        return plan
    }

    /// Notes the workout Lifting saved to Apple Health for a session.
    mutating func recordSavedHealthWorkout(_ workoutID: UUID, for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var link = sessions[index].health ?? HealthLink()
        link.savedWorkoutID = workoutID
        sessions[index].health = link
    }

    /// Removes a session's Apple Health match and stops future matching for it.
    mutating func unlinkHealth(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].health = HealthLink(savedWorkoutID: sessions[index].health?.savedWorkoutID, unlinked: true)
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
