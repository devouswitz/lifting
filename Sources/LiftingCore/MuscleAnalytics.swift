import Foundation

public struct MuscleSummary: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var directSets: Int = 0
    public var secondarySets: Int = 0
    public var volume: Double = 0
    public var reps: Int = 0
    public var sessions: Set<UUID> = []
    public func setCount(includeSecondary: Bool) -> Double { Double(directSets) + (includeSecondary ? Double(secondarySets) * 0.5 : 0) }
}

public extension TrainingData {
    func muscleSummary(programID: UUID? = nil, since: Date = .distantPast, until: Date = .distantFuture) -> [MuscleSummary] {
        var result: [String: MuscleSummary] = [:]
        func name(_ value: String) -> String {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Other" : cleaned.localizedCapitalized
        }
        for session in sessions(inProgram: programID) where session.startedAt >= since && session.startedAt < until && session.skipped != true {
            for item in session.exercises where item.mode != .cardio {
                let sets = item.sets.filter { $0.completedAt != nil && $0.plan.kind != .warmup }
                guard !sets.isEmpty else { continue }
                let primary = name(item.muscle ?? exercise(item.exerciseID)?.muscle ?? "Other")
                var entry = result[primary] ?? MuscleSummary(name: primary)
                entry.directSets += sets.count; entry.sessions.insert(session.id)
                entry.reps += sets.compactMap(\.reps).reduce(0, +)
                entry.volume += sets.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
                result[primary] = entry
                for secondary in Set((item.secondaryMuscles ?? exercise(item.exerciseID)?.secondaryMuscles ?? []).map(name)) where secondary != primary {
                    var other = result[secondary] ?? MuscleSummary(name: secondary)
                    other.secondarySets += sets.count; other.sessions.insert(session.id)
                    result[secondary] = other
                }
            }
        }
        return result.values.sorted { $0.directSets == $1.directSets ? $0.name < $1.name : $0.directSets > $1.directSets }
    }
}
