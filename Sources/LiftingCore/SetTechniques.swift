import Foundation

public enum SetTechniques {
    public static func drops(workingWeight: Double, rounding: Double, reductionPercent: Double = 20, count: Int = 1, reps: Int? = 10, repCeiling: Int? = nil, rpe: Double? = nil, seconds: Double? = nil, meters: Double? = nil, amrap: Bool = false) -> [SetPlan] {
        let total = max(1, min(count, 10))
        return (1...total).map { index in
            let fraction = pow(1 - max(0, min(reductionPercent, 100)) / 100, Double(index))
            return SetPlan(kind: .drop, load: .percent, percent: fraction * 100, reps: reps, repCeiling: repCeiling, seconds: seconds, meters: meters, rpe: rpe, amrap: amrap, restSeconds: index == total ? nil : 0)
        }
    }
    public static func myo(activationReps: Int = 15, miniReps: Int = 5, miniSets: Int = 4, rest: Int = 20) -> [SetPlan] {
        let count = max(1, min(miniSets, 20))
        return [SetPlan(kind: .myoActivation, reps: activationReps, repCeiling: nil, rpe: 9, amrap: true, restSeconds: rest)] + (0..<count).map { index in
            SetPlan(kind: .myoMini, reps: miniReps, repCeiling: nil, rpe: nil, restSeconds: index == count - 1 ? nil : rest)
        }
    }
    public static func myo(activation: SetPlan, mini: SetPlan, miniSets: Int, rest: Int) -> [SetPlan] {
        var first = activation; first.id = UUID(); first.kind = .myoActivation; first.restSeconds = rest
        let count = max(1, min(miniSets, 20))
        return [first] + (0..<count).map { i in
            var copy = mini; copy.id = UUID(); copy.kind = .myoMini; copy.restSeconds = i == count - 1 ? nil : rest
            return copy
        }
    }
}

public extension TrainingData {
    mutating func setWorkingWeight(_ weight: Double, for exerciseID: UUID, saveFuture: Bool) throws {
        guard weight.isFinite, weight >= 0, weight <= 100_000,
              let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let v = variants.firstIndex(where: { $0.id == activeSession!.exercises[e].variantID }) else { throw TrainingError.invalid("Enter a valid working weight.") }
        for s in activeSession!.exercises[e].sets.indices where activeSession!.exercises[e].sets[s].completedAt == nil {
            let plan = activeSession!.exercises[e].sets[s].plan
            if plan.load == .working || plan.load == .percent { activeSession!.exercises[e].sets[s].weight = plan.resolvedWeight(working: weight, increment: activeSession!.exercises[e].roundingIncrement ?? variants[v].rounding) }
        }
        activeSession!.exercises[e].workingWeight = weight
        if saveFuture { variants[v].workingWeight = weight }
    }

    mutating func applyTechnique(to exerciseID: UUID, plans: [SetPlan], isDrop: Bool, replaceRemaining: Bool, saveFuture: Bool) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let v = variants.firstIndex(where: { $0.id == activeSession!.exercises[e].variantID }) else { throw TrainingError.invalid("Exercise unavailable.") }
        guard activeSession!.exercises[e].mode != .cardio else { throw TrainingError.invalid("Use intervals for cardio.") }
        let old = activeSession!.exercises[e]
        let currentLoad = old.workingLoad(fallback: variants[v].workingWeight)
        let base = isDrop ? (old.sets.last(where: { $0.completedAt != nil && $0.plan.kind != .warmup })?.weight ?? old.sets.last(where: { $0.plan.kind != .warmup })?.weight ?? currentLoad) : currentLoad
        if replaceRemaining { activeSession!.exercises[e].sets.removeAll { $0.completedAt == nil && $0.plan.kind != .warmup } }
        if isDrop, let last = activeSession!.exercises[e].sets.indices.last { activeSession!.exercises[e].sets[last].plan.restSeconds = 0; restDeadline = nil }
        var liveVariant = variants[v]; liveVariant.workingWeight = base; liveVariant.rounding = old.roundingIncrement ?? variants[v].rounding
        var adjusted = plans
        if old.mode == .bodyweight { for p in adjusted.indices { adjusted[p].load = .none } }
        activeSession!.exercises[e].sets.append(contentsOf: adjusted.map { LoggedSet(plan: $0, variant: liveVariant) })
        if saveFuture {
            if replaceRemaining { variants[v].sets.removeAll { $0.kind != .warmup } }
            if isDrop, let last = variants[v].sets.indices.last { variants[v].sets[last].restSeconds = 0 }
            variants[v].sets.append(contentsOf: adjusted)
        }
    }

    mutating func addSessionSet(to exerciseID: UUID, warmup: Bool = false) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }), let variant = variant(activeSession!.exercises[e].variantID) else { throw TrainingError.invalid("Exercise unavailable.") }
        let item = activeSession!.exercises[e]
        var set = item.sets.last ?? LoggedSet(plan: SetPlan(), variant: variant)
        set.id = UUID(); set.plan.id = UUID(); set.completedAt = nil
        if warmup {
            var current = variant; current.workingWeight = item.workingLoad(fallback: variant.workingWeight); current.rounding = item.roundingIncrement ?? variant.rounding
            set = LoggedSet(plan: SetPlan(kind: .warmup, load: .percent, reps: 5, repCeiling: nil), variant: current)
        }
        else if set.plan.kind == .myoMini || set.plan.kind == .myoActivation {
            let rest = item.sets.last(where: { $0.plan.kind == .myoActivation })?.plan.restSeconds ?? 20
            if let last = activeSession!.exercises[e].sets.indices.last { activeSession!.exercises[e].sets[last].plan.restSeconds = rest }
            set.plan.kind = .myoMini; set.plan.amrap = false; set.plan.restSeconds = nil
            if item.sets.last?.plan.kind == .myoActivation { set.reps = 5; set.plan.reps = 5; set.plan.repCeiling = nil }
        }
        if set.plan.repRange != nil || set.plan.reps == nil { set.reps = nil }
        activeSession!.exercises[e].sets.append(set)
    }
}
