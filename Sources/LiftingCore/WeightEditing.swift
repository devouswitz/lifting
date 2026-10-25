import Foundation

public extension Variant {
    /// Warm-ups use the first working set; later working sets inherit the nearest entry.
    var referenceWeight: Double {
        sets.first(where: { $0.kind != .warmup && $0.load != .none })?
            .resolvedWeight(working: workingWeight, increment: rounding) ?? workingWeight
    }

    var resolvedWeights: [Double?] {
        let firstWeight = referenceWeight
        var inherited = workingWeight
        return sets.map { plan in
            if plan.kind == .warmup {
                return plan.resolvedWeight(working: firstWeight, increment: rounding)
            }
            let weight = plan.resolvedWeight(working: inherited, increment: rounding)
            if plan.load == .working, let weight { inherited = weight }
            return weight
        }
    }

    func weight(for plan: SetPlan) -> Double? {
        guard let index = sets.firstIndex(where: { $0.id == plan.id }) else {
            return plan.resolvedWeight(working: referenceWeight, increment: rounding)
        }
        return resolvedWeights[index]
    }

    mutating func setWeight(_ weight: Double, for setID: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        if sets[index].load == .working {
            sets[index].weightOverride = weight
            if index == sets.firstIndex(where: { $0.kind != .warmup && $0.load == .working }) {
                workingWeight = weight
            }
        } else {
            sets[index].load = .fixed
            sets[index].fixedWeight = weight
        }
    }

    /// Progression changes matching anchors as well as the legacy base.
    mutating func progressWeight(to weight: Double) {
        let previous = referenceWeight
        for index in sets.indices where sets[index].load == .working && sets[index].weightOverride == previous {
            sets[index].weightOverride = weight
        }
        workingWeight = weight
    }
}

public extension SessionExercise {
    /// Classify older saves before changing their base. Unequal entries stay independent.
    fileprivate mutating func resolveLegacyWeightEntries(fallback: Double) {
        let base = workingWeight ?? fallback
        for index in sets.indices where sets[index].weightIsEdited == nil {
            let expected = sets[index].plan.resolvedWeight(working: base, increment: roundingIncrement ?? 0)
            let actual = sets[index].weight
            sets[index].weightIsEdited = actual.flatMap { a in expected.map { abs(a - $0) > 0.00001 } } ?? (actual != expected)
        }
    }

    /// Working-weight sets, and bodyweight sets whose entry is the added or assisted load.
    private func followsEntries(_ plan: SetPlan) -> Bool { plan.load == .working || (mode == .bodyweight && plan.load == .none) }

    fileprivate mutating func setWeight(_ weight: Double?, at index: Int, fallback: Double) {
        resolveLegacyWeightEntries(fallback: fallback)
        sets[index].weight = weight
        sets[index].weightIsEdited = true
        if sets[index].completedAt == nil, followsEntries(sets[index].plan), sets[index].plan.kind != .warmup {
            for next in sets.indices.dropFirst(index + 1) {
                let set = sets[next]
                if set.plan.kind == .warmup { continue }
                // An explicit entry or completed working set starts its own chain.
                if followsEntries(set.plan) && (set.weightIsEdited == true || set.completedAt != nil) { break }
                guard set.completedAt == nil, set.weightIsEdited != true,
                      followsEntries(set.plan) || set.plan.load == .percent else { continue }
                if set.plan.load == .none { sets[next].weight = weight; continue }
                sets[next].weight = weight.flatMap { set.plan.resolvedWeight(working: $0, increment: roundingIncrement ?? 0) }
            }
        }
        workingWeight = workingLoad(fallback: fallback)
        for warmup in sets.indices where sets[warmup].plan.kind == .warmup && sets[warmup].completedAt == nil && sets[warmup].weightIsEdited != true {
            sets[warmup].weight = sets[warmup].plan.resolvedWeight(working: workingWeight ?? fallback, increment: roundingIncrement ?? 0)
        }
    }
}

public extension TrainingData {
    mutating func setLoggedWeight(_ weight: Double?, exerciseID: UUID, setID: UUID) throws {
        guard let exerciseIndex = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }),
              weight.map({ $0.isFinite && abs($0) <= 100_000 && ($0 >= 0 || activeSession!.exercises[exerciseIndex].mode == .bodyweight) }) ?? true,
              let setIndex = activeSession?.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }),
              let variant = variant(activeSession!.exercises[exerciseIndex].variantID) else {
            throw TrainingError.invalid("Enter a valid weight.")
        }
        activeSession!.exercises[exerciseIndex].roundingIncrement = activeSession!.exercises[exerciseIndex].roundingIncrement ?? variant.rounding
        activeSession!.exercises[exerciseIndex].setWeight(weight, at: setIndex, fallback: variant.workingWeight)
    }

    /// Save each entered load to its matching prescribed set without changing other days.
    mutating func saveSessionWeights(_ exerciseID: UUID) throws {
        guard let item = activeSession?.exercises.first(where: { $0.id == exerciseID }),
              let index = variants.firstIndex(where: { $0.id == item.variantID }) else {
            throw TrainingError.invalid("Exercise unavailable.")
        }
        variants[index].workingWeight = item.workingLoad(fallback: variants[index].workingWeight)
        var ordinals: [SetKind: Int] = [:]
        for set in item.sets where set.plan.kind != .warmup {
            let ordinal = ordinals[set.plan.kind, default: 0]
            ordinals[set.plan.kind] = ordinal + 1
            let matchingKind = variants[index].sets.indices.filter { variants[index].sets[$0].kind == set.plan.kind }
            let planIndex = variants[index].sets.firstIndex(where: { $0.id == set.plan.id })
                ?? (matchingKind.indices.contains(ordinal) ? matchingKind[ordinal] : nil)
            guard let weight = set.weight, let planIndex else { continue }
            if variants[index].sets[planIndex].load == .working {
                variants[index].setWeight(weight, for: variants[index].sets[planIndex].id)
                if set.weightIsEdited == false { variants[index].sets[planIndex].weightOverride = nil }
            } else if variants[index].sets[planIndex].load == .fixed {
                variants[index].sets[planIndex].fixedWeight = weight
            }
        }
    }
}
