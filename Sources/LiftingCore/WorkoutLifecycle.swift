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
        guard let session = activeSession else { return }
        activeSession!.exercises = session.exercises.movingLinked(exerciseID, relativeTo: targetID, after: after) { $0.group }
    }
    mutating func moveSessionExercise(_ exerciseID: UUID, offset: Int) {
        guard let session = activeSession else { return }
        activeSession!.exercises = session.exercises.movingLinked(exerciseID, by: offset) { $0.group }
    }
    mutating func moveSlot(_ slotID: UUID, routineID: UUID, relativeTo targetID: UUID, after: Bool) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }) else { return }
        routines[r].slots = routines[r].slots.movingLinked(slotID, relativeTo: targetID, after: after) { $0.group }
    }
    mutating func moveSlot(_ slotID: UUID, routineID: UUID, offset: Int) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }) else { return }
        routines[r].slots = routines[r].slots.movingLinked(slotID, by: offset) { $0.group }
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

extension Array where Element: Identifiable, Element.ID == UUID {
    /// Moves an item before or after a target. A superset or circuit moves as one block, gathered together if
    /// its members had drifted apart, and nothing lands inside a group: a drop on a member goes before or after it.
    func movingLinked(_ id: UUID, relativeTo targetID: UUID, after: Bool, group: (Element) -> String?) -> [Element] {
        let keys = map { group($0).flatMap { $0.isEmpty ? nil : $0 } }
        guard let source = firstIndex(where: { $0.id == id }), let target = firstIndex(where: { $0.id == targetID }) else { return self }
        let moving = indices.filter { $0 == source || (keys[source] != nil && keys[$0] == keys[source]) }
        guard !moving.contains(target) else { return self }
        let landing = indices.filter { $0 == target || (keys[target] != nil && keys[$0] == keys[target]) }
        let edge = after ? landing.last! + 1 : landing.first!
        var result = self.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moving.map { self[$0] }, at: edge - moving.filter { $0 < edge }.count)
        return result
    }

    /// Moves an item, with its group, past the neighbouring item or group.
    func movingLinked(_ id: UUID, by offset: Int, group: (Element) -> String?) -> [Element] {
        let keys = map { group($0).flatMap { $0.isEmpty ? nil : $0 } }
        guard let source = firstIndex(where: { $0.id == id }) else { return self }
        let members = indices.filter { $0 == source || (keys[source] != nil && keys[$0] == keys[source]) }
        let neighbour = offset < 0 ? members.first! - 1 : members.last! + 1
        guard indices.contains(neighbour) else { return self }
        return movingLinked(id, relativeTo: self[neighbour].id, after: offset > 0, group: group)
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
