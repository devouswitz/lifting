import Foundation

public extension TrainingData {
    mutating func addExerciseToSession(_ exerciseID: UUID) throws {
        guard let session = activeSession, let exercise = exercise(exerciseID) else { throw TrainingError.invalid("Workout or exercise unavailable.") }
        let current = session.exercises.first { $0.exerciseID == exerciseID }.flatMap { variant($0.variantID) }
        let prescribed = session.routineID.flatMap(routine)?.slots.compactMap { variant($0.variantID) }.first { $0.exerciseID == exerciseID }
        let previous = sessions.sorted { $0.startedAt > $1.startedAt }.lazy.filter { $0.routineID == session.routineID && (session.routineID != nil || $0.name == session.name) }
            .flatMap(\.exercises).first { $0.exerciseID == exerciseID && $0.mode == exercise.mode }.flatMap { variant($0.variantID) }
        let base = [session.programID.flatMap(program)?.name, session.name].compactMap { $0 }.joined(separator: " · ")
        let selected = current ?? prescribed ?? previous ?? Variant.standard(for: exercise, label: Self.uniqueName(base, among: variants.filter { $0.exerciseID == exerciseID }.map(\.label)))
        if variant(selected.id) == nil { variants.append(selected) }
        activeSession!.exercises.append(SessionExercise(variant: selected, exercise: exercise))
    }

    mutating func setExerciseExpanded(_ exerciseID: UUID, expanded: Bool, focus: Bool = false) {
        guard var session = activeSession, let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        if focus { for i in session.exercises.indices { session.exercises[i].collapsed = i != index } }
        session.exercises[index].collapsed = !expanded
        if session.exercises[index].sets.allSatisfy({ $0.completedAt != nil }) { session.exercises[index].keepExpanded = expanded }
        activeSession = session
    }

    mutating func setAllExercisesExpanded(_ expanded: Bool) {
        guard var session = activeSession else { return }
        for i in session.exercises.indices {
            session.exercises[i].collapsed = !expanded
            if session.exercises[i].sets.allSatisfy({ $0.completedAt != nil }) { session.exercises[i].keepExpanded = expanded }
        }
        activeSession = session
    }

    @discardableResult mutating func collapseCompletedExercise(_ exerciseID: UUID) -> UUID? {
        guard settings.autoCollapseCompleted == true, var session = activeSession,
              let index = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              !session.exercises[index].sets.isEmpty, session.exercises[index].sets.allSatisfy({ $0.completedAt != nil }), session.exercises[index].keepExpanded != true else { return nil }
        session.exercises[index].collapsed = true
        let pending = session.exercises.indices.filter { i in session.exercises[i].sets.contains { $0.completedAt == nil } }
        let next = pending.first(where: { $0 > index }) ?? pending.first
        if let next { session.exercises[next].collapsed = false }
        activeSession = session
        return next.map { session.exercises[$0].id }
    }

    mutating func replaceSetPlan(exerciseID: UUID, setID: UUID, plan: SetPlan) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = activeSession?.exercises[e].sets.firstIndex(where: { $0.id == setID }),
              let variant = variant(activeSession!.exercises[e].variantID) else { throw TrainingError.invalid("Set unavailable.") }
        let item = activeSession!.exercises[e]
        activeSession!.exercises[e].sets[s].plan = plan
        if item.sets[s].completedAt == nil {
            activeSession!.exercises[e].sets[s].weight = plan.resolvedWeight(working: item.workingLoad(fallback: variant.workingWeight), increment: item.roundingIncrement ?? variant.rounding)
            activeSession!.exercises[e].sets[s].reps = plan.initialReps
            activeSession!.exercises[e].sets[s].seconds = plan.seconds
            activeSession!.exercises[e].sets[s].meters = plan.meters
            activeSession!.exercises[e].sets[s].rpe = plan.rpe
        }
    }

    mutating func moveSessionExercise(_ exerciseID: UUID, offset: Int) {
        guard let index = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }), activeSession!.exercises.indices.contains(index + offset) else { return }
        activeSession!.exercises.swapAt(index, index + offset)
    }
}

public extension Variant {
    static func standard(for exercise: Exercise, label: String) -> Variant {
        var variant = Variant(exerciseID: exercise.id, label: label)
        if exercise.mode == .cardio { variant.sets = [SetPlan(load: .none, reps: nil, repCeiling: nil, seconds: 1200, rpe: 6)]; variant.restSeconds = 0 }
        if exercise.mode == .bodyweight { variant.sets = (0..<3).map { _ in SetPlan(load: .none) } }
        return variant
    }
}
