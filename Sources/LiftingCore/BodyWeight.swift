import Foundation

/// One weigh-in, stored in kilograms like every other load.
public struct BodyWeightEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kilograms: Double
    public init(id: UUID = UUID(), date: Date, kilograms: Double) {
        self.id = id; self.date = date; self.kilograms = kilograms
    }
    public var isValid: Bool { kilograms.isFinite && (1...1000).contains(kilograms) }
}

public extension TrainingData {
    /// The latest weigh-in on or before a date.
    func bodyWeight(at date: Date) -> Double? {
        bodyWeights.filter { $0.date <= date }.max { $0.date < $1.date }?.kilograms
    }

    mutating func saveBodyWeight(_ entry: BodyWeightEntry) throws {
        guard entry.isValid else { throw TrainingError.invalid("Enter a body weight between 1 and 1,000 kg.") }
        if let index = bodyWeights.firstIndex(where: { $0.id == entry.id }) { bodyWeights[index] = entry } else { bodyWeights.append(entry) }
        bodyWeights.sort { $0.date < $1.date }
        refreshSessionBodyWeights()
    }

    mutating func removeBodyWeight(_ id: UUID) {
        bodyWeights.removeAll { $0.id == id }
        refreshSessionBodyWeights()
    }

    /// Each finished workout uses the weigh-in in effect when it ended, so a late or corrected entry
    /// updates bodyweight volume for the workouts it covers.
    mutating func refreshSessionBodyWeights() {
        for index in sessions.indices {
            let weight = bodyWeight(at: sessions[index].endedAt ?? sessions[index].startedAt)
            if sessions[index].bodyWeight != weight { sessions[index].bodyWeight = weight }
        }
    }
}
