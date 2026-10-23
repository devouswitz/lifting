import Foundation

public extension SessionExercise {
    /// Legacy saves have no edit marker. Preserve values that differ from their prescription.
    fileprivate func inheritsWeight(at index: Int, fallback: Double) -> Bool {
        let set = sets[index]
        if let edited = set.weightIsEdited { return !edited }
        let expected = set.plan.resolvedWeight(working: workingLoad(fallback: fallback), increment: roundingIncrement ?? 0)
        guard let actual = set.weight, let expected else { return set.weight == expected }
        return abs(actual - expected) < 0.00001
    }

    fileprivate mutating func updateWorkingWeight(_ weight: Double, fallback: Double, after source: Int? = nil, preservingEntries: Bool = true) {
        let inherited = Set(sets.indices.filter { !preservingEntries || inheritsWeight(at: $0, fallback: fallback) })
        for index in sets.indices where sets[index].weightIsEdited == nil {
            sets[index].weightIsEdited = !inherited.contains(index)
        }
        for index in inherited where sets[index].completedAt == nil {
            let plan = sets[index].plan
            guard plan.load == .working || plan.load == .percent else { continue }
            // Earlier warm-ups still follow the new base; earlier work sets keep their entries.
            if let source, index <= source, plan.kind != .warmup { continue }
            sets[index].weight = plan.resolvedWeight(working: weight, increment: roundingIncrement ?? 0)
            sets[index].weightIsEdited = false
        }
        workingWeight = weight
    }
}

public extension TrainingData {
    mutating func setLoggedWeight(_ weight: Double?, exerciseID: UUID, setID: UUID) throws {
        guard weight.map({ $0.isFinite && (0...100_000).contains($0) }) ?? true,
              var session = activeSession,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }),
              let variant = variant(session.exercises[exerciseIndex].variantID) else {
            throw TrainingError.invalid("Enter a valid weight.")
        }
        var item = session.exercises[exerciseIndex]
        item.roundingIncrement = item.roundingIncrement ?? variant.rounding
        let set = item.sets[setIndex]
        if let weight, set.completedAt == nil, set.plan.load == .working, set.plan.kind != .warmup {
            item.updateWorkingWeight(weight, fallback: variant.workingWeight, after: setIndex)
        }
        item.sets[setIndex].weight = weight
        item.sets[setIndex].weightIsEdited = true
        session.exercises[exerciseIndex] = item
        activeSession = session
    }

    /// An explicit change to the header replaces the remaining linked loads. Fixed sets stay fixed.
    mutating func setWorkingWeight(_ weight: Double, for exerciseID: UUID, saveFuture: Bool) throws {
        guard weight.isFinite, (0...100_000).contains(weight), var session = activeSession,
              let index = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let variantIndex = variants.firstIndex(where: { $0.id == session.exercises[index].variantID }) else {
            throw TrainingError.invalid("Enter a valid working weight.")
        }
        var item = session.exercises[index]
        item.roundingIncrement = item.roundingIncrement ?? variants[variantIndex].rounding
        item.updateWorkingWeight(weight, fallback: variants[variantIndex].workingWeight, preservingEntries: false)
        session.exercises[index] = item
        activeSession = session
        if saveFuture { variants[variantIndex].workingWeight = weight }
    }
}

public extension Variant {
    /// A normal work set edits the shared base. Fixed and percentage sets remain independent.
    mutating func setWeight(_ weight: Double, for setID: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        if sets[index].load == .working { workingWeight = weight }
        else { sets[index].load = .fixed; sets[index].fixedWeight = weight }
    }
}
