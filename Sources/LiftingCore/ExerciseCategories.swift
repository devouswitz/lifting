import Foundation

/// Categories stay in exercise records, so custom labels travel with existing backups and sync.
public enum ExerciseCategory: String, CaseIterable {
    case equipment, muscle

    public var defaults: [String] {
        switch self {
        case .equipment:
            return ["Barbell", "Dumbbell", "Cable", "Machine", "Smith Machine", "Bodyweight", "Kettlebell", "Resistance Band", "Suspension Trainer", "Plate", "Bike", "Rower", "Treadmill", "Other"]
        case .muscle:
            return ["Chest", "Back", "Shoulders", "Arms", "Biceps", "Triceps", "Forearms", "Core", "Legs", "Quadriceps", "Hamstrings", "Glutes", "Calves", "Adductors", "Abductors", "Traps", "Cardio", "Full Body", "Other"]
        }
    }

    public func choices(in exercises: [Exercise]) -> [String] {
        let existing = exercises.flatMap { exercise in
            self == .equipment ? [exercise.equipment] : [exercise.muscle] + (exercise.secondaryMuscles ?? [])
        }
        var seen = Set<String>()
        return (defaults + existing).map(Self.clean).filter {
            !$0.isEmpty && seen.insert(Self.key($0)).inserted
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func clean(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func key(_ name: String) -> String {
        clean(name).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Reuse a category rather than creating a second spelling of the same name.
    public static func resolve(_ name: String, choices: [String]) -> String? {
        let clean = clean(name)
        guard !clean.isEmpty, clean.count <= 200 else { return nil }
        return choices.first { key($0) == key(clean) } ?? clean
    }
}
