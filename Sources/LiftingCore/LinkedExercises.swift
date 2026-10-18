import Foundation

public extension Session {
    func linkedExercises(for id: UUID) -> [SessionExercise] {
        guard let key = exercises.first(where: { $0.id == id })?.group, !key.isEmpty else { return [] }
        let members = exercises.filter { $0.group == key }
        return Set(members.map { $0.slotID ?? $0.id }).count > 1 ? members : []
    }
    func linkTitle(for id: UUID) -> String? {
        let members = linkedExercises(for: id)
        guard !members.isEmpty else { return nil }
        let count = Set(members.map { $0.slotID ?? $0.id }).count
        return count > 2 ? "Circuit" : "Superset"
    }
}

public extension TrainingData {
    mutating func linkRoutineExercises(routineID: UUID, slots ids: Set<UUID>, rest: Int, transition: Int = 0) throws {
        guard let r = routines.firstIndex(where: { $0.id == routineID }), ids.count >= 2,
              ids.isSubset(of: Set(routines[r].slots.map(\.id))), (0...86400).contains(rest), (0...86400).contains(transition) else { throw TrainingError.invalid("Choose at least two exercises and valid rest times.") }
        let key = UUID().uuidString
        for i in routines[r].slots.indices where ids.contains(routines[r].slots[i].id) {
            routines[r].slots[i].group = key
            routines[r].slots[i].groupRestSeconds = rest; routines[r].slots[i].transitionSeconds = transition
        }
        cleanRoutineGroups(r)
    }
    mutating func unlinkRoutineGroup(routineID: UUID, group: String) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }) else { return }
        for i in routines[r].slots.indices where routines[r].slots[i].group == group { routines[r].slots[i].group = ""; routines[r].slots[i].groupRestSeconds = nil; routines[r].slots[i].transitionSeconds = nil }
    }
    private mutating func cleanRoutineGroups(_ r: Int) {
        let counts = Dictionary(grouping: routines[r].slots.filter { !$0.group.isEmpty }, by: \.group)
        for i in routines[r].slots.indices where counts[routines[r].slots[i].group]?.count == 1 { routines[r].slots[i].group = ""; routines[r].slots[i].groupRestSeconds = nil; routines[r].slots[i].transitionSeconds = nil }
    }
    mutating func linkSessionExercises(_ ids: Set<UUID>, rest: Int, transition: Int = 0, saveFuture: Bool = false) throws {
        guard let session = activeSession, ids.count >= 2, ids.isSubset(of: Set(session.exercises.map(\.id))),
              (0...86400).contains(rest), (0...86400).contains(transition) else { throw TrainingError.invalid("Choose at least two exercises and valid rest times.") }
        let key = UUID().uuidString
        for i in activeSession!.exercises.indices where ids.contains(activeSession!.exercises[i].id) {
            activeSession!.exercises[i].group = key; activeSession!.exercises[i].groupRestSeconds = rest; activeSession!.exercises[i].transitionSeconds = transition
        }
        if saveFuture, let routineID = session.routineID {
            let slots = Set(session.exercises.filter { ids.contains($0.id) }.compactMap(\.slotID))
            guard session.exercises.filter({ ids.contains($0.id) }).allSatisfy({ $0.slotID != nil }), slots.count >= 2 else { throw TrainingError.invalid("Save added exercises to the day before linking future sessions.") }
            try linkRoutineExercises(routineID: routineID, slots: slots, rest: rest, transition: transition)
        }
        restDeadline = nil
    }
    mutating func unlinkSessionGroup(_ group: String, saveFuture: Bool = false) {
        guard let session = activeSession else { return }
        for i in activeSession!.exercises.indices where activeSession!.exercises[i].group == group {
            activeSession!.exercises[i].group = nil; activeSession!.exercises[i].groupRestSeconds = nil; activeSession!.exercises[i].transitionSeconds = nil
        }
        if saveFuture, let r = session.routineID {
            let slots = Set(session.exercises.filter { $0.group == group }.compactMap(\.slotID))
            if let index = routines.firstIndex(where: { $0.id == r }) {
                for i in routines[index].slots.indices where slots.contains(routines[index].slots[i].id) { routines[index].slots[i].group = ""; routines[index].slots[i].groupRestSeconds = nil; routines[index].slots[i].transitionSeconds = nil }
            }
        }
        restDeadline = nil
    }
    mutating func advanceLinkedFlow(after exerciseID: UUID, setID: UUID, now: Date) {
        guard let session = activeSession, let current = session.exercises.first(where: { $0.id == exerciseID }),
              let logged = current.sets.first(where: { $0.id == setID }), session.linkTitle(for: exerciseID) != nil else { return }
        let members = session.linkedExercises(for: exerciseID)
        guard let index = members.firstIndex(where: { $0.id == exerciseID }) else { return }
        let pendingWarmups = members.filter { $0.sets.contains { $0.completedAt == nil && $0.plan.kind == .warmup } }
        var target: SessionExercise?
        var rest = logged.plan.restSeconds ?? current.restSeconds
        if !pendingWarmups.isEmpty {
            target = pendingWarmups.first(where: { $0.id == exerciseID }) ?? pendingWarmups.first
        } else if logged.plan.kind == .warmup {
            target = members.first { $0.sets.contains { $0.completedAt == nil } }
        } else if let next = current.sets.first(where: { $0.completedAt == nil }), [.drop, .myoMini].contains(next.plan.kind) {
            // Finish a drop/MYO chain before advancing to the next linked movement.
            target = current
            if next.plan.kind == .drop { rest = 0 }
        } else {
            let order = Array(members.indices.dropFirst(index + 1)) + Array(members.indices.prefix(index + 1))
            if let next = order.first(where: { i in members[i].sets.contains { $0.completedAt == nil } }) {
                target = members[next]
                rest = next <= index ? (current.groupRestSeconds ?? current.restSeconds) : (current.transitionSeconds ?? 0)
            } else { rest = current.groupRestSeconds ?? current.restSeconds }
        }
        restDeadline = settings.autoRest && rest > 0 ? now.addingTimeInterval(Double(rest)) : nil
        if let target { setExerciseExpanded(target.id, expanded: true, focus: true) }
    }
}
