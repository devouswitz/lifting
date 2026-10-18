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
