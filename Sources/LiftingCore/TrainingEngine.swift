import Foundation

public extension TrainingData {
    mutating func start(routineID: UUID, now: Date = Date()) throws {
        guard activeSession == nil else { throw TrainingError.invalid("Finish or discard the current workout first.") }
        guard let routine = routines.first(where: { $0.id == routineID }), !routine.slots.isEmpty else { throw TrainingError.invalid("Add an exercise to this day first.") }
        let items = try routine.slots.map { slot -> SessionExercise in
            guard let variant = variant(slot.variantID), let exercise = exercise(variant.exerciseID) else { throw TrainingError.invalid("An exercise is missing.") }
            var item = SessionExercise(variant: variant, exercise: exercise, slotID: slot.id)
            item.group = slot.group.isEmpty ? nil : slot.group
            item.groupRestSeconds = slot.groupRestSeconds; item.transitionSeconds = slot.transitionSeconds
            return item
        }
        let owner = programForDay(routine.id)
        activeSession = Session(routineID: routine.id, name: routine.name, startedAt: now, exercises: items)
        activeSession?.programID = owner?.id
        activeSession?.programName = owner?.name
        activeSession?.advancesProgram = owner?.nextDayID == routine.id
        for index in activeSession!.exercises.indices { activeSession!.exercises[index].collapsed = index != 0 }
        activeSession?.notes = routine.notes
        restDeadline = nil
    }

    mutating func toggleSet(exerciseID: UUID, setID: UUID, now: Date = Date()) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = activeSession?.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
        if activeSession!.exercises[e].sets[s].completedAt == nil {
            if activeSession?.pausedAt != nil { setWorkoutPaused(false, now: now) }
            try Self.validateLoggedSet(activeSession!.exercises[e].sets[s])
            activeSession!.exercises[e].sets[s].completedAt = now
            activeSession!.exercises[e].keepExpanded = nil
            endMyoClusterIfMissed(exercise: e, set: s)
            let rest = activeSession!.exercises[e].sets[s].plan.restSeconds ?? activeSession!.exercises[e].restSeconds
            restDeadline = settings.autoRest && rest > 0 ? now.addingTimeInterval(Double(rest)) : nil
            advanceLinkedFlow(after: exerciseID, setID: setID, now: now)
        } else {
            activeSession!.exercises[e].sets[s].completedAt = nil
            restDeadline = nil
        }
    }

    /// MYO mini-sets continue until one misses its target. The miss ends the cluster: the pending
    /// mini-sets right after it are removed and the exercise's normal rest follows.
    private mutating func endMyoClusterIfMissed(exercise e: Int, set s: Int) {
        let set = activeSession!.exercises[e].sets[s]
        guard set.plan.kind == .myoMini, let goal = set.plan.reps, let reps = set.reps, reps < goal else { return }
        var sets = activeSession!.exercises[e].sets
        var end = s + 1
        while end < sets.count, sets[end].plan.kind == .myoMini, sets[end].completedAt == nil { end += 1 }
        sets.removeSubrange((s + 1)..<end)
        sets[s].plan.restSeconds = nil
        activeSession!.exercises[e].sets = sets
    }

    mutating func finish(now: Date = Date()) throws {
        guard var session = activeSession, session.completedSets > 0 else { throw TrainingError.invalid("Log a set before finishing, or discard this workout.") }
        if let paused = session.pausedAt {
            session.pauses = (session.pauses ?? []) + [DateInterval(start: paused, end: max(paused, now))]
            session.pausedAt = nil
        }
        session.endedAt = max(now, session.startedAt)
        for item in session.exercises where item.progressionEligible {
            guard let v = variants.firstIndex(where: { $0.id == item.variantID }), variants[v].progression.mode != .manual else { continue }
            let reference = variants[v].referenceWeight
            let sets = item.sets.filter { $0.plan.kind == .working || $0.plan.kind == .failure }
            guard !sets.isEmpty, item.sets.filter({ $0.plan.kind != .warmup }).allSatisfy({ $0.completedAt != nil }),
                  sets.allSatisfy({ ($0.reps != nil || $0.plan.amrap) && $0.weight != nil && $0.plan.load == .working }),
                  sets.allSatisfy({ abs(($0.weight ?? 0) - reference) < 0.001 }) else { continue }
            let mode = variants[v].progression.mode
            func target(_ plan: SetPlan) -> Int { mode == .double ? (plan.repCeiling ?? plan.reps ?? 1) : (plan.reps ?? 1) }
            // AMRAP sets count as done when completed; a logged count only has to reach the goal.
            let passed = sets.allSatisfy { set in set.plan.amrap ? (set.reps ?? .max) >= (set.plan.reps ?? 0) : (set.reps ?? 0) >= target(set.plan) }
            if passed {
                variants[v].progressWeight(to: reference + variants[v].progression.increment)
                variants[v].progression.failures = 0
            } else {
                // Double progression is successful within its rep range, but does not add weight yet.
                let failed = sets.contains { !$0.plan.amrap && ($0.reps ?? 0) < ($0.plan.reps ?? 1) }
                if failed { variants[v].progression.failures += 1 }
                else { variants[v].progression.failures = 0 }
                let limit = variants[v].progression.deloadAfter
                if limit > 0 && variants[v].progression.failures >= limit {
                    let target = reference * (1 - variants[v].progression.deloadPercent / 100)
                    let step = variants[v].rounding
                    variants[v].progressWeight(to: step > 0 ? floor(target / step) * step : target)
                    variants[v].progression.failures = 0
                }
            }
        }
        session.bodyWeight = bodyWeight(at: session.endedAt!)
        sessions.append(session)
        if session.advancesProgram == true, let programID = session.programID, let dayID = session.routineID,
           let p = programs.firstIndex(where: { $0.id == programID }), programs[p].nextDayID == dayID, let day = programs[p].dayIDs.firstIndex(of: dayID) {
            programs[p].nextDayIndex = (day + 1) % programs[p].dayIDs.count
        }
        activeSession = nil; restDeadline = nil
    }

    mutating func substitute(sessionExerciseID: UUID, with exerciseID: UUID, future: Bool) throws {
        guard let index = activeSession?.exercises.firstIndex(where: { $0.id == sessionExerciseID }),
              let exercise = exercise(exerciseID), let source = variant(activeSession!.exercises[index].variantID) else { throw TrainingError.invalid("Exercise unavailable.") }
        let old = activeSession!.exercises[index]
        guard old.exerciseID != exerciseID else { return }
        let pending = old.sets.filter { $0.completedAt == nil }
        guard !pending.isEmpty else { throw TrainingError.invalid("All sets are complete. Add another exercise instead.") }
        let replacement = substitutionVariant(from: source, to: exercise)
        var item = SessionExercise(variant: replacement, exercise: exercise, slotID: old.slotID)
        item.group = old.group; item.groupRestSeconds = old.groupRestSeconds; item.transitionSeconds = old.transitionSeconds
        item.substitutedFrom = old.name
        let completed = old.sets.filter { $0.completedAt != nil }
        if completed.isEmpty { item.notes = old.notes }
        if exercise.mode == old.mode {
            // Preserve today's structure, including edited targets, drop sets, and MYO mini-sets.
            item.sets = pending.map { logged in
                var plan = logged.plan; plan.id = UUID(); plan.weightOverride = nil
                plan.seconds = logged.seconds; plan.meters = logged.meters; plan.rpe = logged.rpe
                if plan.load == .fixed { plan.fixedWeight = 0 }
                var replacementSet = LoggedSet(plan: plan, variant: replacement)
                replacementSet.reps = logged.reps
                return replacementSet
            }
            item.restSeconds = old.restSeconds
        }
        if !completed.isEmpty {
            activeSession!.exercises[index].sets = completed
            activeSession!.exercises[index].progressionEligible = false
            item.progressionEligible = false
            activeSession!.exercises.insert(item, at: index + 1)
        } else { activeSession!.exercises[index] = item }
        if future, let routineID = activeSession!.routineID,
           let r = routines.firstIndex(where: { $0.id == routineID }),
           let s = routines[r].slots.firstIndex(where: { $0.id == old.slotID }) {
            routines[r].slots[s].variantID = replacement.id
        }
        restDeadline = nil
    }

    /// The track an exercise uses when it stands in for another. Returning to an exercise resumes
    /// its own track, so each substitute keeps one variant per original.
    mutating func substitutionVariant(from source: Variant, to exercise: Exercise) -> Variant {
        let originID = source.substitutionSourceID ?? source.id
        if let existing = variants.first(where: { $0.exerciseID == exercise.id && ($0.substitutionSourceID ?? $0.id) == originID }) { return existing }
        let sourceMode = self.exercise(source.exerciseID)?.mode
        var replacement = Variant.standard(for: exercise, label: Self.uniqueName(source.label, among: variants.filter { $0.exerciseID == exercise.id }.map(\.label)))
        replacement.restSeconds = exercise.mode == .cardio ? 0 : source.restSeconds
        replacement.substitutionSourceID = originID
        if exercise.mode == sourceMode {
            replacement.sets = source.sets.map { plan in
                var copy = plan; copy.id = UUID(); copy.fixedWeight = 0; copy.weightOverride = nil
                if exercise.mode == .bodyweight { copy.load = .none }
                return copy
            }
        }
        variants.append(replacement)
        return replacement
    }

    /// Points a day's exercise slot at another exercise, such as the same movement on other equipment.
    mutating func swapSlotExercise(routineID: UUID, slotID: UUID, to exerciseID: UUID) throws {
        guard let r = routines.firstIndex(where: { $0.id == routineID }), let s = routines[r].slots.firstIndex(where: { $0.id == slotID }),
              let source = variant(routines[r].slots[s].variantID), let exercise = exercise(exerciseID) else { throw TrainingError.invalid("Exercise unavailable.") }
        guard source.exerciseID != exerciseID else { return }
        routines[r].slots[s].variantID = substitutionVariant(from: source, to: exercise).id
    }

    func points(exerciseID: UUID, variantID: UUID? = nil, metric: Metric, since: Date = .distantPast) -> [ProgressPoint] {
        sessions.filter { $0.startedAt >= since }.sorted { $0.startedAt < $1.startedAt }.compactMap { session in
            let items = session.exercises.filter { $0.exerciseID == exerciseID && (variantID == nil || $0.variantID == variantID) }
            let completed = items.flatMap { item in item.sets.filter { $0.completedAt != nil && $0.plan.kind != .warmup }.map { (set: $0, load: item.load(of: $0, bodyWeight: session.bodyWeight)) } }
            let sets = completed.map(\.set)
            guard !sets.isEmpty else { return nil }
            let values: [Double]
            switch metric {
            case .weight: values = sets.compactMap(\.weight)
            case .volume: values = completed.compactMap { s in guard let w = s.load, let reps = s.set.reps else { return nil }; return w * Double(reps) }
            case .estimatedMax: values = completed.compactMap { s in guard let w = s.load, let reps = s.set.reps, reps > 0, reps <= 12 else { return nil }; return reps == 1 ? w : w * (1 + Double(reps) / 30) }
            case .reps: values = sets.compactMap { $0.reps.map(Double.init) }
            case .duration: values = sets.compactMap { $0.seconds.map { $0 / 60 } }
            case .distance: values = sets.compactMap { $0.meters.map { $0 / 1000 } }
            case .rpe: values = sets.compactMap(\.rpe)
            }
            guard !values.isEmpty else { return nil }
            let sum: Bool = [.volume, .reps, .duration, .distance].contains(metric)
            let value = sum ? values.reduce(0, +) : metric == .rpe ? values.reduce(0, +) / Double(values.count) : values.max()!
            return ProgressPoint(id: session.id, date: session.startedAt, value: value)
        }
    }

    static func validateLoggedSet(_ set: LoggedSet) throws {
        if let weight = set.weight, !weight.isFinite || abs(weight) > 10_000_000 { throw TrainingError.invalid("Enter a valid weight.") }
        for value in [set.seconds, set.meters].compactMap({ $0 }) {
            guard value.isFinite && value >= 0 && value <= 10_000_000 else { throw TrainingError.invalid("Enter a valid nonnegative value.") }
        }
        if let reps = set.reps, !(0...10000).contains(reps) { throw TrainingError.invalid("Reps must be between 0 and 10,000.") }
        if let rpe = set.rpe, !rpe.isFinite || !(0...10).contains(rpe) { throw TrainingError.invalid("RPE must be between 0 and 10.") }
        guard set.reps != nil || set.seconds != nil || set.meters != nil || set.rpe != nil || set.weight != nil || set.plan.reps != nil || set.plan.amrap else { throw TrainingError.invalid("Enter reps, time, distance, weight, or RPE.") }
    }

    func validated() throws -> TrainingData {
        guard schemaVersion == 1 else { throw TrainingError.invalid("This backup uses an unsupported version.") }
        func unique<T: Identifiable>(_ values: [T]) -> Bool where T.ID == UUID { Set(values.map(\.id)).count == values.count }
        guard unique(exercises), unique(variants), unique(routines), unique(sessions), sessions.count <= 100_000 else { throw TrainingError.invalid("The backup contains duplicate or excessive records.") }
        guard historyImports.count <= 100_000, Set(historyImports.map(\.sourceVariantID)).count == historyImports.count,
              historyImports.allSatisfy({ link in exercise(link.exerciseID) != nil && variant(link.variantID)?.exerciseID == link.exerciseID }),
              Dictionary(grouping: historyImports, by: \.sourceExerciseID).values.allSatisfy({ Set($0.map(\.exerciseID)).count == 1 }) else { throw TrainingError.invalid("The backup contains invalid history import references.") }
        let substitutionKeys = variants.map { "\($0.substitutionSourceID ?? $0.id)|\($0.exerciseID)" }
        guard Set(substitutionKeys).count == substitutionKeys.count,
              variants.allSatisfy({ value in value.substitutionSourceID.map { origin in variant(origin).map { $0.substitutionSourceID == nil } ?? false } ?? true }) else { throw TrainingError.invalid("The backup contains invalid substitution references.") }
        let ownedDays = programs.flatMap(\.dayIDs)
        guard unique(programs), Set(ownedDays).count == ownedDays.count,
              programs.allSatisfy({ p in !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && p.name.count <= 200 && p.dayIDs.allSatisfy { routine($0) != nil } && (p.dayIDs.isEmpty ? p.nextDayIndex == 0 : p.dayIDs.indices.contains(p.nextDayIndex)) }),
              activeProgramID.map({ program($0) != nil }) ?? true else { throw TrainingError.invalid("The backup contains invalid programs or days.") }
        func number(_ n: Double, max: Double = 10_000_000) -> Bool { n.isFinite && n >= 0 && n <= max }
        func group(_ key: String?, rest: Int?, transition: Int?) -> Bool { (key?.count ?? 0) <= 200 && (rest.map { (0...86400).contains($0) } ?? true) && (transition.map { (0...86400).contains($0) } ?? true) }
        guard exercises.allSatisfy({ $0.muscle.count <= 200 && ($0.secondaryMuscles ?? []).count <= 50 && ($0.secondaryMuscles ?? []).allSatisfy { $0.count <= 200 } }),
              routines.flatMap(\.slots).allSatisfy({ group($0.group, rest: $0.groupRestSeconds, transition: $0.transitionSeconds) }) else { throw TrainingError.invalid("Invalid muscle groups or linked exercise settings.") }
        guard unique(customSetTypes), customSetTypes.count <= 100, customSetTypes.allSatisfy(\.isValid),
              Set(customSetTypes.map { $0.name.lowercased() }).count == customSetTypes.count,
              (settings.quickAdd ?? []).count <= 4, (settings.quickAdd ?? []).allSatisfy({ ["drop", "myo", "warmup", "failure", "working", "myoActivation", "myoMini"].contains($0) || ($0.hasPrefix("type:") && UUID(uuidString: String($0.dropFirst(5))) != nil) }) else { throw TrainingError.invalid("Invalid set types.") }
        guard unique(bodyWeights), bodyWeights.count <= 100_000, bodyWeights.allSatisfy(\.isValid),
              settings.techniques?.isValid ?? true, exercises.allSatisfy({ $0.techniques?.isValid ?? true }),
              settings.restStep.map({ (1...600).contains($0) }) ?? true else { throw TrainingError.invalid("Invalid body weight or workout settings.") }
        guard unique(warmupPresets), warmupPresets.count <= 10000, warmupPresets.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 && (1...1000).contains($0.sets.count) && unique($0.sets) && $0.sets.allSatisfy { $0.kind == .warmup && $0.isValid } }) else { throw TrainingError.invalid("Invalid warm-up preset.") }
        guard exercises.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 }),
              variants.allSatisfy({ v in exercise(v.exerciseID) != nil && !v.label.isEmpty && v.label.count <= 200 && number(v.workingWeight) && number(v.rounding) && (0...86400).contains(v.restSeconds) && (0...1000).contains(v.sets.count) && unique(v.sets) && v.sets.allSatisfy(\.isValid) && number(v.progression.increment) && number(v.progression.deloadPercent, max: 100) && (0...100).contains(v.progression.deloadAfter) && (0...1000).contains(v.progression.failures) }),
              routines.allSatisfy({ r in !r.name.isEmpty && r.name.count <= 200 && unique(r.slots) && r.slots.allSatisfy { variant($0.variantID) != nil } }),
              number(settings.barWeight), (settings.platesLB + settings.platesKG).allSatisfy({ number($0) && $0 > 0 }), ["system", "light", "dark"].contains(settings.theme), settings.colors?.isValid ?? true else { throw TrainingError.invalid("The backup contains invalid exercises or prescriptions.") }
        for session in sessions + [activeSession].compactMap({ $0 }) {
            let pauses = session.pauses ?? []
            var previousEnd = session.startedAt
            guard pauses.count <= 1000 else { throw TrainingError.invalid("Too many workout pauses.") }
            for pause in pauses {
                guard pause.start >= previousEnd, pause.duration.isFinite, pause.duration >= 0,
                      (session.endedAt ?? session.pausedAt).map({ pause.end <= $0 }) ?? true else {
                    throw TrainingError.invalid("Invalid workout pauses.")
                }
                previousEnd = pause.end
            }
            guard session.pausedAt.map({ $0 >= previousEnd && session.endedAt == nil }) ?? true,
                  (session.programName?.count ?? 0) <= 200, unique(session.exercises),
                  session.endedAt.map({ $0 >= session.startedAt }) ?? true, session.health?.isValid ?? true,
                  session.bodyWeight.map({ $0.isFinite && (1...1000).contains($0) }) ?? true else {
                throw TrainingError.invalid("Invalid session records.")
            }
            for item in session.exercises {
                guard group(item.group, rest: item.groupRestSeconds, transition: item.transitionSeconds), (item.muscle?.count ?? 0) <= 200, (item.secondaryMuscles ?? []).count <= 50, (item.secondaryMuscles ?? []).allSatisfy({ $0.count <= 200 }) else { throw TrainingError.invalid("Invalid workout muscle or group settings.") }
                guard variant(item.variantID)?.exerciseID == item.exerciseID, exercise(item.exerciseID) != nil, unique(item.sets), (0...86400).contains(item.restSeconds), number(item.timerElapsed), item.workingWeight.map({ number($0) }) ?? true, item.roundingIncrement.map({ number($0) }) ?? true, item.sets.allSatisfy({ $0.plan.isValid }) else { throw TrainingError.invalid("A session references a missing exercise or variant.") }
                for set in item.sets { try Self.validateLoggedSet(set) }
            }
        }
        guard sessions.allSatisfy({ $0.endedAt != nil }), activeSession?.endedAt == nil,
              activeSession.map({ !sessions.map(\.id).contains($0.id) }) ?? true else { throw TrainingError.invalid("Invalid active workout.") }
        return self
    }
}

public enum PlateCalculator {
    public static func plates(total: Double, bar: Double, available: [Double]) -> (plates: [Double], remainder: Double) {
        guard total.isFinite, bar.isFinite, total >= bar, bar >= 0 else { return ([], max(0, total - bar)) }
        var perSide = (total - bar) / 2
        var result: [Double] = []
        for plate in available.filter({ $0.isFinite && $0 > 0 }).sorted(by: >) {
            while perSide + 0.00001 >= plate && result.count < 200 { result.append(plate); perSide -= plate }
        }
        return (result, max(0, perSide * 2))
    }
}
