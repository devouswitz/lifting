import Foundation

public extension Session {
    mutating func changeStart(to date: Date) {
        let offset = date.timeIntervalSince(startedAt)
        startedAt = date
        endedAt = endedAt?.addingTimeInterval(offset)
        pausedAt = pausedAt?.addingTimeInterval(offset)
        lastActivityAt = lastActivityAt?.addingTimeInterval(offset)
        pauses = pauses?.map { DateInterval(start: $0.start.addingTimeInterval(offset), duration: $0.duration) }
        for index in exercises.indices {
            exercises[index].timerStartedAt = exercises[index].timerStartedAt?.addingTimeInterval(offset)
            for set in exercises[index].sets.indices {
                exercises[index].sets[set].completedAt = exercises[index].sets[set].completedAt?.addingTimeInterval(offset)
            }
        }
    }
}

public extension TrainingData {
    mutating func setWorkoutPaused(_ paused: Bool, now: Date = Date()) {
        guard var session = activeSession else { return }
        if paused, session.pausedAt == nil {
            session.pausedAt = now
            restDeadline = nil
            for index in session.exercises.indices {
                if let start = session.exercises[index].timerStartedAt {
                    session.exercises[index].timerElapsed += max(0, now.timeIntervalSince(start))
                    session.exercises[index].timerStartedAt = nil
                }
            }
        } else if !paused, let start = session.pausedAt {
            session.pauses = (session.pauses ?? []) + [DateInterval(start: start, end: max(start, now))]
            session.pausedAt = nil
        }
        session.lastActivityAt = now
        activeSession = session
    }

    mutating func moveSessionExercise(_ exerciseID: UUID, relativeTo targetID: UUID, after: Bool = false) {
        guard var session = activeSession, exerciseID != targetID,
              let source = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              session.exercises.contains(where: { $0.id == targetID }) else { return }
        let item = session.exercises.remove(at: source)
        guard let target = session.exercises.firstIndex(where: { $0.id == targetID }) else { return }
        session.exercises.insert(item, at: target + (after ? 1 : 0))
        activeSession = session
    }

    mutating func addExercises(_ exerciseIDs: [UUID], to routineID: UUID) throws {
        guard let index = routines.firstIndex(where: { $0.id == routineID }),
              exerciseIDs.allSatisfy({ exercise($0) != nil }) else { throw TrainingError.invalid("Day or exercise unavailable.") }
        let base = [programForDay(routineID)?.name, routines[index].name].compactMap { $0 }.joined(separator: " · ")
        for id in exerciseIDs {
            guard let exercise = exercise(id) else { continue }
            let label = Self.uniqueName(base, among: variants.filter { $0.exerciseID == id }.map(\.label))
            let variant = Variant.standard(for: exercise, label: label)
            variants.append(variant)
            routines[index].slots.append(RoutineSlot(variantID: variant.id))
        }
    }
}

public enum WorkoutReminder {
    public static let idleDelay: TimeInterval = 45 * 60
    public static let pausedDelay: TimeInterval = 30 * 60

    public static func dates(for session: Session) -> [Date] {
        guard session.endedAt == nil else { return [] }
        let anchor = session.lastActivityAt ?? session.pausedAt ?? session.startedAt
        let first = anchor.addingTimeInterval(session.pausedAt == nil ? idleDelay : pausedDelay)
        return [first, first.addingTimeInterval(90 * 60)]
    }

    public static func isOverdue(_ session: Session, at now: Date) -> Bool {
        dates(for: session).first.map { $0 <= now } ?? false
    }
}
