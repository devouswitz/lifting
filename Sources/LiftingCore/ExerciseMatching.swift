import Foundation

enum ExerciseMatching {
    static func identity(_ exercise: Exercise) -> (name: String, equipment: String) {
        var name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines), equipment = exercise.equipment.lowercased()
        for suffix in ["Barbell", "Dumbbell", "Cable", "Machine", "Smith Machine", "Bodyweight", "Kettlebell"] {
            let ending = " (\(suffix))"
            if name.lowercased().hasSuffix(ending.lowercased()) {
                name = String(name.dropLast(ending.count)); if equipment.isEmpty { equipment = suffix.lowercased() }; break
            }
        }
        return (name.lowercased().filter { $0.isLetter || $0.isNumber }, equipment)
    }
    static func match(_ source: Exercise, among exercises: [Exercise]) -> Exercise? {
        let key = identity(source)
        let candidates = exercises.filter { value in
            let other = identity(value)
            return source.mode == value.mode && key.name == other.name && (key.equipment.isEmpty || key.equipment == other.equipment)
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}

/// Exercises that are the same movement on different equipment, such as Barbell and Dumbbell Bench Press.
/// Grouped by name, so existing exercises join a family without any migration. Each keeps its own history.
public enum EquipmentFamily {
    static let abbreviations = ["bb": "Barbell", "db": "Dumbbell", "kb": "Kettlebell"]
    /// Equipment that can swap for one another during a lift.
    public static let choices = ["Barbell", "Dumbbell", "Cable", "Machine", "Smith Machine", "Kettlebell", "Resistance Band", "Bodyweight"]

    /// The equipment word in a name, with its range, longest match first so "Smith Machine" beats "Machine".
    static func equipmentWord(in name: String) -> (equipment: String, range: Range<String.Index>)? {
        let words = (choices + abbreviations.keys).sorted { $0.count > $1.count }
        for word in words {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return (abbreviations[word] ?? word, range)
            }
        }
        return nil
    }

    /// "Bench Press" for "Dumbbell Bench Press", "Bench Press (Barbell)", or "DB bench press".
    public static func movement(_ exercise: Exercise) -> String {
        var name = exercise.name
        while let match = equipmentWord(in: name) { name.removeSubrange(match.range) }
        return name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func equipment(_ exercise: Exercise) -> String {
        let field = ExerciseCategory.clean(exercise.equipment)
        if !field.isEmpty { return field }
        return equipmentWord(in: exercise.name)?.equipment ?? (exercise.mode == .bodyweight ? "Bodyweight" : "")
    }

    /// The name for the same movement on other equipment, keeping the original's wording and case.
    public static func name(for exercise: Exercise, equipment: String) -> String {
        var name = exercise.name
        if let match = equipmentWord(in: name) {
            let original = String(name[match.range])
            name.replaceSubrange(match.range, with: original.first?.isUppercase == false ? equipment.lowercased() : equipment)
            return name
        }
        let words = name.split(separator: " ")
        let sentenceCase = words.dropFirst().allSatisfy { $0.first?.isLowercase == true }
        return "\(equipment) \(sentenceCase && words.count > 1 ? name.prefix(1).lowercased() + name.dropFirst() : name)"
    }
}

public extension TrainingData {
    /// Every exercise for the same movement, including this one, ordered by equipment.
    func equipmentFamily(of exerciseID: UUID) -> [Exercise] {
        guard let exercise = exercise(exerciseID), exercise.mode != .cardio else { return [] }
        let movement = EquipmentFamily.movement(exercise)
        guard !movement.isEmpty else { return [exercise] }
        return exercises.filter { $0.mode != .cardio && EquipmentFamily.movement($0) == movement }
            .sorted { EquipmentFamily.equipment($0).localizedStandardCompare(EquipmentFamily.equipment($1)) == .orderedAscending }
    }

    /// The family member on the given equipment, created from this exercise when there is none yet.
    mutating func equipmentVersion(of exerciseID: UUID, equipment: String) throws -> Exercise {
        guard let source = exercise(exerciseID) else { throw TrainingError.invalid("Exercise unavailable.") }
        if let existing = equipmentFamily(of: exerciseID).first(where: { ExerciseCategory.key(EquipmentFamily.equipment($0)) == ExerciseCategory.key(equipment) }) { return existing }
        var created = Exercise(name: EquipmentFamily.name(for: source, equipment: equipment), muscle: source.muscle, equipment: equipment,
                               mode: equipment == "Bodyweight" ? .bodyweight : source.mode == .bodyweight ? .strength : source.mode)
        created.secondaryMuscles = source.secondaryMuscles
        created.techniques = source.techniques
        exercises.append(created)
        return created
    }
}
