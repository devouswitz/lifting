import Foundation
import CryptoKit

public enum ImportField: String, CaseIterable, Identifiable, Sendable {
    case date, workout, exercise, mode, weight, weightUnit, reps, repMaximum, seconds, distance, distanceUnit, rpe, kind, setIndex, notes, workoutNotes, endedAt, workoutDuration, program, muscle, equipment, group, sessionID
    public var id: Self { self }
    public var title: String {
        switch self {
        case .date: return "Date / start time"
        case .workout: return "Workout name"
        case .exercise: return "Exercise"
        case .mode: return "Exercise type"
        case .rpe: return "RPE"
        case .weightUnit: return "Weight unit"
        case .repMaximum: return "Maximum reps"
        case .seconds: return "Set duration"
        case .distanceUnit: return "Distance unit"
        case .kind: return "Set type"
        case .setIndex: return "Set number"
        case .notes: return "Exercise notes"
        case .workoutNotes: return "Workout notes"
        case .endedAt: return "End time"
        case .workoutDuration: return "Workout duration"
        case .sessionID: return "Workout ID"
        default: return rawValue.capitalized
        }
    }
}

public struct ExternalCSVOptions: Sendable {
    public var source: String
    public var columns: [ImportField: String]
    public var weightUnit: WeightUnit = .kg
    public var distanceUnit: String = "m"
    public var timeUnit: String = "s"
    public var dateFormat: String = ""
    public var programName: String = ""
    public init(source: String = "CSV", columns: [ImportField: String] = [:]) { self.source = source; self.columns = columns }
}

public enum ExternalHistoryCSV {
    public static func normalized(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
    public static func detect(_ headers: [String]) -> ExternalCSVOptions {
        let lookup = Dictionary(headers.map { (normalized($0), $0) }, uniquingKeysWith: { first, _ in first })
        var options = ExternalCSVOptions()
        if lookup["exercisetitle"] != nil && lookup["starttime"] != nil { options.source = "Hevy" }
        else if lookup["workoutname"] != nil && lookup["exercisename"] != nil { options.source = "Strong" }
        else if lookup["category"] != nil && lookup["date"] != nil && lookup["exercise"] != nil { options.source = "FitNotes" }
        let aliases: [ImportField: [String]] = [
            .date: ["start_time", "date", "started_at", "start", "timestamp"], .workout: ["title", "workout_name", "workout", "routine", "day"],
            .exercise: ["exercise_title", "exercise_name", "exercise", "movement"], .weight: ["weight_kg", "weight_lb", "weight_lbs", "weight", "load"],
            .mode: ["exercise_type", "exercise_mode", "mode"],
            .weightUnit: ["weight_unit", "weight_units", "unit"], .reps: ["reps", "repetitions", "rep_min", "min_reps"], .repMaximum: ["rep_max", "max_reps", "rep_ceiling"],
            .seconds: ["duration_seconds", "seconds", "time", "set_duration"], .distance: ["distance_km", "distance_miles", "distance_meters", "distance_m", "distance", "meters"], .distanceUnit: ["distance_unit", "distance_units"],
            .rpe: ["rpe"], .kind: ["set_type", "kind", "type", "set_order"], .setIndex: ["set_index", "set_order", "set_number", "set"],
            .notes: ["exercise_notes", "notes", "comment"], .workoutNotes: ["description", "workout_notes", "session_notes"],
            .endedAt: ["end_time", "ended_at", "end"], .workoutDuration: ["workout_duration", "duration"], .program: ["program", "program_name", "plan"],
            .muscle: ["muscle", "muscle_group", "category"], .equipment: ["equipment"], .group: ["superset_id", "superset", "group", "circuit"], .sessionID: ["workout_id", "session_id"]
        ]
        for (field, names) in aliases { options.columns[field] = names.compactMap { lookup[normalized($0)] }.first }
        if normalized(options.columns[.weight] ?? "").contains("lb") { options.weightUnit = .lb }
        let distance = normalized(options.columns[.distance] ?? "")
        if distance.contains("km") { options.distanceUnit = "km" } else if distance.contains("mile") { options.distanceUnit = "mi" }
        return options
    }
    public static func stableID(_ value: String) -> UUID {
        let b = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
    public static func decode(_ bytes: Data, options: ExternalCSVOptions) throws -> HistoryBundle {
        let table = try CSVCodec.parse(bytes), headers = table[0]
        guard Set(headers).count == headers.count, options.columns[.date] != nil, options.columns[.exercise] != nil else { throw TrainingError.invalid("Map the date and exercise columns before importing.") }
        var data = TrainingData(), occurrences: [String: Int] = [:]
        let catalog = TrainingData.starter().exercises
        var warnings: Set<String> = ["Workout history only. Exported files may not contain saved routines or progression rules."]
        let formatter = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dates = DateFormatter(); dates.locale = Locale(identifier: "en_US_POSIX"); dates.isLenient = false
        func parseDate(_ text: String, row: Int) throws -> Date {
            if let value = fractional.date(from: text) ?? formatter.date(from: text) { return value }
            let formats = options.dateFormat.isEmpty ? ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd MMM yyyy, HH:mm", "dd MMM yyyy, HH:mm:ss", "dd MMM yyyy HH:mm", "MMM d, yyyy h:mm a"] : [options.dateFormat]
            for format in formats { dates.dateFormat = format; if let value = dates.date(from: text) { return value } }
            throw TrainingError.invalid("Unrecognized date on row \(row). Choose its date format in Import options.")
        }
        for (offset, values) in table.dropFirst().enumerated() {
            let row = offset + 2, raw = Dictionary(uniqueKeysWithValues: zip(headers, values))
            func text(_ field: ImportField) -> String { CSVCodec.unprotect(raw[options.columns[field] ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            func numeric(_ field: ImportField) throws -> Double? {
                let input = text(field); if input.isEmpty { return nil }
                guard let value = Double(input.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0, value <= 10_000_000 else { throw TrainingError.invalid("Invalid \(field.title.lowercased()) on row \(row).") }
                return value
            }
            func duration(_ field: ImportField, unit: String) throws -> Double? {
                let value = text(field); if value.isEmpty { return nil }
                if value.contains(":") {
                    let parts = value.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
                    guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 && $0!.isFinite }), parts.dropFirst().allSatisfy({ $0! < 60 }) else { throw TrainingError.invalid("Invalid duration on row \(row).") }
                    return parts.reduce(0) { $0 * 60 + $1! }
                }
                // Strong also exports durations such as 1h 12m 3s.
                if value.contains(where: { $0.isLetter }) {
                    let regex = try NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*([hms])", options: .caseInsensitive)
                    let source = value as NSString, matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
                    let remainder = regex.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: source.length), withTemplate: "").trimmingCharacters(in: .whitespaces)
                    guard !matches.isEmpty, remainder.isEmpty else { throw TrainingError.invalid("Invalid duration on row \(row).") }
                    return matches.reduce(0) { total, match in
                        let n = Double(source.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "."))!
                        let suffix = source.substring(with: match.range(at: 2)).lowercased()
                        return total + n * (suffix == "h" ? 3600 : suffix == "m" ? 60 : 1)
                    }
                }
                return try numeric(field).map { $0 * (unit == "min" ? 60 : 1) }
            }
            let name = text(.exercise)
            guard !name.isEmpty else { throw TrainingError.invalid("Missing exercise on row \(row).") }
            let started = try parseDate(text(.date), row: row)
            let workout = text(.workout).isEmpty ? "Imported workout" : text(.workout)
            let ended = try text(.endedAt).isEmpty ? started.addingTimeInterval(try duration(.workoutDuration, unit: "s") ?? 0) : parseDate(text(.endedAt), row: row)
            let program = text(.program).isEmpty ? options.programName : text(.program)
            let namespace = options.source.lowercased()
            let sessionKey = text(.sessionID).isEmpty ? "\(started.timeIntervalSince1970)|\(workout)|\(program)" : text(.sessionID)
            let sessionID = stableID("\(namespace)|session|\(sessionKey)")
            let weightUnit = text(.weightUnit).isEmpty ? options.weightUnit.rawValue : text(.weightUnit).lowercased()
            guard ["kg", "kgs", "kilograms", "lb", "lbs", "pounds"].contains(weightUnit) else { throw TrainingError.invalid("Unknown weight unit on row \(row).") }
            let weight = try numeric(.weight).map { weightUnit.hasPrefix("lb") || weightUnit == "pounds" ? WeightUnit.lb.kilograms($0) : $0 }
            let seconds = try duration(.seconds, unit: options.timeUnit)
            let distanceUnit = text(.distanceUnit).isEmpty ? options.distanceUnit : text(.distanceUnit).lowercased()
            guard ["m", "meter", "meters", "km", "kilometers", "mi", "mile", "miles"].contains(distanceUnit) else { throw TrainingError.invalid("Unknown distance unit on row \(row).") }
            let meters = try numeric(.distance).map { $0 * (distanceUnit == "km" || distanceUnit == "kilometers" ? 1000 : ["mi", "mile", "miles"].contains(distanceUnit) ? 1609.344 : 1) }
            let repValue = try numeric(.reps), ceiling = try numeric(.repMaximum)
            guard [repValue, ceiling].compactMap({ $0 }).allSatisfy({ $0.rounded() == $0 && $0 <= 10000 }) else { throw TrainingError.invalid("Reps must be whole numbers on row \(row).") }
            let reps = repValue.map(Int.init), rpe = try numeric(.rpe)
            let exerciseKey = ExerciseMatching.identity(Exercise(name: name, equipment: text(.equipment)))
            let known = catalog.first { item in let candidate = ExerciseMatching.identity(item); return candidate.name == exerciseKey.name && (exerciseKey.equipment.isEmpty || exerciseKey.equipment == candidate.equipment) }
            let mode: ExerciseMode
            if !text(.mode).isEmpty {
                switch normalized(text(.mode)) {
                case "strength", "weightreps", "weightandreps", "weightedduration": mode = .strength
                case "bodyweight", "weightedbodyweight", "assistedbodyweight", "repsonly", "reps", "duration": mode = .bodyweight
                case "cardio", "distance", "distanceduration", "distanceandduration": mode = .cardio
                default: throw TrainingError.invalid("Unknown exercise type on row \(row).")
                }
            } else if let known { mode = known.mode }
            else if (reps ?? 0) > 0 || (weight ?? 0) > 0 { mode = weight != nil ? .strength : .bodyweight }
            else { mode = (seconds ?? 0) > 0 || (meters ?? 0) > 0 ? .cardio : weight != nil ? .strength : .bodyweight }
            let exerciseID = stableID("\(namespace)|exercise|\(name)|\(text(.equipment))|\(mode.rawValue)")
            if data.exercise(exerciseID) == nil { data.exercises.append(Exercise(id: exerciseID, name: name, muscle: text(.muscle).isEmpty ? "Other" : text(.muscle), equipment: text(.equipment), mode: mode)) }
            let variantID = stableID("\(namespace)|variant|\(exerciseID)|\(workout)|\(program)")
            if data.variant(variantID) == nil { data.variants.append(Variant(id: variantID, exerciseID: exerciseID, label: [program, workout].filter { !$0.isEmpty }.joined(separator: " · "))) }
            if !data.sessions.contains(where: { $0.id == sessionID }) {
                var session = Session(id: sessionID, name: workout, startedAt: started, endedAt: ended)
                session.notes = text(.workoutNotes); session.programName = program.isEmpty ? nil : program
                session.programID = program.isEmpty ? nil : stableID("\(namespace)|program|\(program)")
                data.sessions.append(session)
            }
            let s = data.sessions.firstIndex { $0.id == sessionID }!
            guard data.sessions[s].startedAt == started, data.sessions[s].endedAt == ended else { throw TrainingError.invalid("Conflicting workout times on row \(row).") }
            let e: Int
            if let index = data.sessions[s].exercises.firstIndex(where: { $0.variantID == variantID && $0.group == (text(.group).isEmpty ? nil : text(.group)) }) { e = index }
            else {
                var item = SessionExercise(variant: data.variant(variantID)!, exercise: data.exercise(exerciseID)!)
                item.id = stableID("\(namespace)|item|\(sessionID)|\(variantID)|\(text(.group))")
                item.group = text(.group).isEmpty ? nil : text(.group); item.notes = text(.notes); item.sets = []
                data.sessions[s].exercises.append(item); e = data.sessions[s].exercises.count - 1
            }
            let tag = text(.kind).lowercased()
            let kind: SetKind
            switch tag {
            case "w", "warmup", "warm-up", "warm up": kind = .warmup
            case "d", "drop", "dropset", "drop set": kind = .drop
            case "f", "failure", "failure set": kind = .failure
            case "myoactivation", "myo activation": kind = .myoActivation
            case "myomini", "myo mini": kind = .myoMini
            default:
                kind = .working
                if !tag.isEmpty && !["normal", "working", "work", "n"].contains(tag) && Double(tag) == nil { warnings.insert("Unrecognized set types retained in source fields and logged as working sets.") }
            }
            let plan = SetPlan(kind: kind, load: weight == nil ? .none : .fixed, fixedWeight: weight ?? 0, reps: reps, repCeiling: ceiling.map(Int.init), seconds: seconds, meters: meters, rpe: rpe)
            var set = LoggedSet(plan: plan, variant: data.variant(variantID)!)
            let key = "\(sessionID)|\(variantID)|\(text(.setIndex))|\(text(.group))"
            let ordinal = occurrences[key, default: 0]; occurrences[key] = ordinal + 1
            set.id = stableID("\(namespace)|set|\(key)|\(ordinal)"); set.completedAt = started; set.sourceFields = raw
            data.sessions[s].exercises[e].sets.append(set)
            if !text(.notes).isEmpty && !data.sessions[s].exercises[e].notes.contains(text(.notes)) { data.sessions[s].exercises[e].notes += "\n" + text(.notes) }
        }
        for v in data.variants.indices {
            if let latest = data.sessions.sorted(by: { $0.startedAt > $1.startedAt }).flatMap(\.exercises).first(where: { $0.variantID == data.variants[v].id }) {
                data.variants[v].sets = latest.sets.map(\.plan); data.variants[v].workingWeight = latest.sets.last(where: { $0.plan.kind != .warmup })?.weight ?? 0
            }
        }
        guard !data.sessions.isEmpty else { throw TrainingError.invalid("The file has no logged sets.") }
        if options.columns[.endedAt] == nil && options.columns[.workoutDuration] == nil { warnings.insert("Workout duration is unavailable in this export.") }
        return HistoryBundle(content: try data.validated(), warnings: warnings.sorted())
    }
}
