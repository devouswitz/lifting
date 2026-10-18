import Foundation

public enum ExternalHistoryJSON {
    /// Supports flat set-record arrays and Hevy-style workout/exercise/set exports.
    /// Proprietary databases and encrypted backups are deliberately not guessed.
    public static func csv(_ bytes: Data) throws -> Data {
        guard bytes.count <= 25_000_000 else { throw TrainingError.invalid("Import files must be under 25 MB.") }
        let object = try JSONSerialization.jsonObject(with: bytes)
        let root = object as? [String: Any]
        if root?["schemaVersion"] != nil { throw TrainingError.invalid("Use Import backup for a Lifting JSON backup.") }
        guard let records = object as? [[String: Any]] ?? root?["workouts"] as? [[String: Any]] ?? root?["records"] as? [[String: Any]] else { throw TrainingError.invalid("Use a set-record JSON array or a workout JSON export containing exercises and sets.") }
        var rows: [[String: Any]] = []
        if records.first?["exercises"] != nil {
            for workout in records {
                guard let exercises = workout["exercises"] as? [[String: Any]] else { throw TrainingError.invalid("An imported workout has no exercise list.") }
                for exercise in exercises {
                    guard let sets = exercise["sets"] as? [[String: Any]] else { throw TrainingError.invalid("An imported exercise has no set list.") }
                    for (index, set) in sets.enumerated() {
                        var row = set
                        row["title"] = workout["title"] ?? workout["name"]
                        row["start_time"] = workout["start_time"] ?? workout["started_at"] ?? workout["date"]
                        row["end_time"] = workout["end_time"] ?? workout["ended_at"]
                        row["description"] = workout["description"] ?? workout["notes"]
                        row["workout_id"] = workout["id"]
                        row["exercise_title"] = exercise["title"] ?? exercise["name"]
                        row["exercise_notes"] = exercise["notes"]
                        row["superset_id"] = exercise["superset_id"]
                        row["set_index"] = set["index"] ?? index
                        row["set_type"] = set["type"] ?? set["set_type"]
                        rows.append(row)
                    }
                }
            }
        } else { rows = records }
        guard !rows.isEmpty, rows.count <= 50_000 else { throw TrainingError.invalid("The JSON has no sets or too many records.") }
        let headers = Set(rows.flatMap { $0.keys }).sorted()
        func string(_ value: Any?) throws -> String {
            guard let value, !(value is NSNull) else { return "" }
            if let text = value as? String { return text }
            if let n = value as? NSNumber { return n.stringValue }
            let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            return String(decoding: bytes, as: UTF8.self)
        }
        return try CSVCodec.render([headers] + rows.map { row in try headers.map { try string(row[$0]) } })
    }
}
