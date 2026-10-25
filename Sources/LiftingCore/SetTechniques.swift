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

public enum Technique: String, Identifiable, Sendable {
    case drop, myo
    public var id: String { rawValue }
    public var title: String { self == .drop ? "Drop sets" : "MYO reps" }
}

/// How a lifter runs drop sets and MYO reps. Set app-wide, and optionally per exercise.
public struct TechniqueDefaults: Codable, Equatable, Sendable {
    /// Targets are templates; sets made from them get their own IDs. A fixed ID keeps equal setups equal.
    private static let target = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var dropPercent: Double = 20
    public var dropCount: Int = 1
    /// Rep, RPE, time, and distance targets for each drop.
    public var drop = SetPlan(id: target, kind: .drop, reps: 10, repCeiling: nil)
    public var activation = SetPlan(id: target, kind: .myoActivation, reps: 15, repCeiling: nil, rpe: 9, amrap: true)
    public var mini = SetPlan(id: target, kind: .myoMini, reps: 5, repCeiling: nil)
    public var miniCount: Int = 4
    public var myoRest: Int = 20
    public init() {}

    public var isValid: Bool {
        dropPercent.isFinite && (0...100).contains(dropPercent) && (1...10).contains(dropCount)
            && (1...20).contains(miniCount) && (0...86400).contains(myoRest)
            && [drop, activation, mini].allSatisfy { $0.isValid && ($0.reps != nil || $0.amrap || $0.rpe != nil || $0.seconds != nil || $0.meters != nil) }
    }

    public func plans(_ technique: Technique) -> [SetPlan] {
        switch technique {
        case .drop:
            return SetTechniques.drops(workingWeight: 0, rounding: 0, reductionPercent: dropPercent, count: dropCount, reps: drop.reps, repCeiling: drop.repCeiling,
                                       rpe: drop.rpe, seconds: drop.seconds, meters: drop.meters, amrap: drop.amrap)
        case .myo:
            return SetTechniques.myo(activation: activation, mini: mini, miniSets: miniCount, rest: myoRest)
        }
    }

    /// Turns one set into a drop set or a MYO set, keeping its identity and any load entered for it.
    /// MYO right after a MYO set continues that cluster as a mini-set; otherwise the set becomes the
    /// activation and the mini-sets that should follow it are returned.
    func convert(_ plan: SetPlan, to technique: Technique, after previous: SetKind?, followedByMini: Bool) -> (set: SetPlan, following: [SetPlan]) {
        var set = plan
        set.customTypeID = nil
        let continuing = technique == .myo && (previous == .myoActivation || previous == .myoMini)
        let target = technique == .drop ? drop : continuing ? mini : activation
        set.reps = target.reps; set.repCeiling = target.repCeiling; set.amrap = target.amrap; set.rpe = target.rpe
        if technique == .drop {
            set.kind = .drop
            // A drop follows the previous set's load, unless a weight was already entered for it.
            if set.load == .working && set.weightOverride == nil { set.load = .percent; set.percent = 100 - dropPercent }
            set.restSeconds = nil
            return (set, [])
        }
        set.kind = continuing ? .myoMini : .myoActivation
        if set.load == .percent { set.load = .working }
        set.restSeconds = myoRest
        guard !continuing, !followedByMini else { return (set, []) }
        return (set, Array(plans(.myo).dropFirst()))
    }
}

public extension TrainingData {
    /// Drop and MYO setup for an exercise: its own, else the app-wide defaults.
    func techniqueDefaults(for exerciseID: UUID?) -> TechniqueDefaults {
        exerciseID.flatMap(exercise)?.techniques ?? settings.techniques ?? TechniqueDefaults()
    }

    /// Converts a live set in place. Drops follow the previous set without rest; MYO adds its mini-sets.
    mutating func convertSessionSet(exerciseID: UUID, setID: UUID, to technique: Technique) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = activeSession!.exercises[e].sets.firstIndex(where: { $0.id == setID }),
              let variant = variant(activeSession!.exercises[e].variantID) else { throw TrainingError.invalid("Set unavailable.") }
        let item = activeSession!.exercises[e]
        let followed = item.sets.indices.contains(s + 1) && item.sets[s + 1].plan.kind == .myoMini
        var converting = item.sets[s].plan
        // An entered weight belongs to the set, not to the drop percentage.
        if item.sets[s].weightIsEdited == true || item.sets[s].completedAt != nil, converting.load == .working { converting.weightOverride = item.sets[s].weight }
        let result = techniqueDefaults(for: item.exerciseID).convert(converting, to: technique, after: s > 0 ? item.sets[s - 1].plan.kind : nil, followedByMini: followed)
        try replaceSetPlan(exerciseID: exerciseID, setID: setID, plan: result.set)
        if technique == .drop {
            // An activation turned into a drop leaves its pending mini-sets behind.
            if item.sets[s].plan.kind == .myoActivation {
                let ids = Set(item.sets.dropFirst(s + 1).prefix { $0.plan.kind == .myoMini && $0.completedAt == nil }.map(\.id))
                activeSession!.exercises[e].sets.removeAll { ids.contains($0.id) }
            }
            if s > 0, item.sets[s - 1].completedAt == nil, item.sets[s - 1].plan.kind != .warmup { activeSession!.exercises[e].sets[s - 1].plan.restSeconds = 0 }
        }
        var live = variant
        live.workingWeight = activeSession!.exercises[e].sets[s].weight ?? item.workingLoad(fallback: variant.workingWeight)
        live.rounding = item.roundingIncrement ?? variant.rounding
        let following = result.following.map { plan -> LoggedSet in
            var copy = plan
            if item.mode != .strength { copy.load = .none }
            return LoggedSet(plan: copy, variant: live)
        }
        activeSession!.exercises[e].sets.insert(contentsOf: following, at: s + 1)
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
        set.id = UUID(); set.plan.id = UUID(); set.completedAt = nil; set.weightIsEdited = false; set.plan.weightOverride = nil
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
        if set.plan.initialReps == nil { set.reps = nil }
        activeSession!.exercises[e].sets.append(set)
    }
}

public extension Variant {
    /// Adds a drop or MYO chain to a saved prescription, as the live workout does.
    mutating func addTechnique(_ technique: Technique, plans: [SetPlan], replacing: Bool) {
        if replacing { sets.removeAll { $0.kind != .warmup } }
        if technique == .drop, let last = sets.indices.last { sets[last].restSeconds = 0 }
        sets.append(contentsOf: plans.map { plan in var copy = plan; copy.id = UUID(); return copy })
    }

    mutating func convertSet(_ id: UUID, to technique: Technique, defaults: TechniqueDefaults) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        let followed = sets.indices.contains(index + 1) && sets[index + 1].kind == .myoMini
        let result = defaults.convert(sets[index], to: technique, after: index > 0 ? sets[index - 1].kind : nil, followedByMini: followed)
        if technique == .drop, sets[index].kind == .myoActivation {
            let ids = Set(sets.dropFirst(index + 1).prefix { $0.kind == .myoMini }.map(\.id))
            sets.removeAll { ids.contains($0.id) }
        }
        sets[index] = result.set
        if technique == .drop, index > 0, sets[index - 1].kind != .warmup { sets[index - 1].restSeconds = 0 }
        sets.insert(contentsOf: result.following, at: index + 1)
    }
}
