import Foundation

public struct RoutineBundle: Sendable {
    public var content: TrainingData
    public var dayCount: Int { content.routines.count }
    public var setCount: Int { content.routines.flatMap(\.slots).reduce(0) { $0 + (content.variant($1.variantID)?.sets.count ?? 0) } }
    public init(content: TrainingData) { self.content = content }
}

public enum RoutineCSV {
    public static let headers = ["format", "record_type", "program_id", "program", "program_notes", "day_order", "day_id", "day", "day_notes", "exercise_order", "slot_id", "exercise_id", "exercise", "mode", "muscle", "equipment", "variant_id", "variant", "working_weight_kg", "rounding_kg", "rest_seconds", "exercise_notes", "progression", "increment_kg", "deload_after", "deload_percent", "group", "set_order", "set_id", "set_type", "load_rule", "fixed_weight_kg", "percent", "reps_min", "reps_max", "seconds", "meters", "rpe", "amrap", "set_rest_seconds"]

    public static func export(_ data: TrainingData, programID: UUID? = nil, dayID: UUID? = nil) throws -> Data {
        let owner = programID.flatMap(data.program)
        guard owner != nil || dayID.flatMap(data.routine) != nil else { throw TrainingError.invalid("Choose a day or program to export.") }
        let ids = owner?.dayIDs ?? [dayID!]
        var rows = [headers]
        func row(_ values: [String: String]) -> [String] { headers.map { values[$0] ?? "" } }
        var base = ["format": "lifting-1", "program_id": owner?.id.uuidString ?? "", "program": owner?.name ?? "", "program_notes": owner?.notes ?? ""]
        if ids.isEmpty { base["record_type"] = "program"; rows.append(row(base)) }
        for (dayOrder, id) in ids.enumerated() {
            guard let day = data.routine(id) else { throw TrainingError.invalid("A program day is missing.") }
            var dayValues = base
            dayValues.merge(["day_order": String(dayOrder + 1), "day_id": day.id.uuidString, "day": day.name, "day_notes": day.notes]) { _, new in new }
            if day.slots.isEmpty { dayValues["record_type"] = "day"; rows.append(row(dayValues)); continue }
            for (exerciseOrder, slot) in day.slots.enumerated() {
                guard let variant = data.variant(slot.variantID), let exercise = data.exercise(variant.exerciseID) else { throw TrainingError.invalid("An exercise is missing.") }
                var values = dayValues
                values.merge(["record_type": "set", "exercise_order": String(exerciseOrder + 1), "slot_id": slot.id.uuidString, "exercise_id": exercise.id.uuidString, "exercise": exercise.name, "mode": exercise.mode.rawValue, "muscle": exercise.muscle, "equipment": exercise.equipment, "variant_id": variant.id.uuidString, "variant": variant.label, "working_weight_kg": String(variant.workingWeight), "rounding_kg": String(variant.rounding), "rest_seconds": String(variant.restSeconds), "exercise_notes": variant.notes, "progression": variant.progression.mode.rawValue, "increment_kg": String(variant.progression.increment), "deload_after": String(variant.progression.deloadAfter), "deload_percent": String(variant.progression.deloadPercent), "group": slot.group]) { _, new in new }
                for (setOrder, plan) in variant.sets.enumerated() {
                    var set = values
                    set["set_order"] = String(setOrder + 1); set["set_id"] = plan.id.uuidString
                    set["set_type"] = plan.kind.rawValue; set["load_rule"] = plan.load.rawValue
                    set["fixed_weight_kg"] = String(plan.fixedWeight); set["percent"] = String(plan.percent)
                    set["reps_min"] = plan.reps.map { String($0) } ?? ""; set["reps_max"] = plan.repCeiling.map { String($0) } ?? ""
                    set["seconds"] = plan.seconds.map { String($0) } ?? ""; set["meters"] = plan.meters.map { String($0) } ?? ""
                    set["rpe"] = plan.rpe.map { String($0) } ?? ""; set["amrap"] = String(plan.amrap)
                    set["set_rest_seconds"] = plan.restSeconds.map { String($0) } ?? ""
                    rows.append(row(set))
                }
            }
        }
        return CSVCodec.render(rows)
    }

    public static func decode(_ bytes: Data) throws -> RoutineBundle {
        let table = try CSVCodec.parse(bytes)
        let header = table[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_") }
        guard Set(header).count == header.count, header.contains("day"), header.contains("exercise") else { throw TrainingError.invalid("A day/program CSV needs day and exercise columns. Use Export CSV on a day or program.") }
        var data = TrainingData()
        var programIDs: [String: UUID] = [:], dayIDs: [String: UUID] = [:], exerciseIDs: [String: UUID] = [:], variantIDs: [String: UUID] = [:]
        var programOrder: [UUID: [Int: UUID]] = [:], slotOrder: [UUID: [Int: RoutineSlot]] = [:], setOrder: [UUID: [Int: SetPlan]] = [:]
        func key(_ id: UUID?, _ fallback: String) -> String { id?.uuidString ?? fallback }
        func required(_ value: String, _ field: String, _ line: Int) throws {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrainingError.invalid("Missing \(field) on CSV row \(line).") }
        }
        for (offset, fields) in table.dropFirst().enumerated() {
            let r = CSVRow(values: Dictionary(uniqueKeysWithValues: zip(header, fields)), number: offset + 2)
            guard ["", "lifting-1"].contains(r.text("format")) else { throw TrainingError.invalid("Unsupported CSV format on row \(r.number).") }
            let record = r.text("record_type", default: "set")
            guard ["program", "day", "set"].contains(record) else { throw TrainingError.invalid("Invalid record_type on row \(r.number).") }
            var programID: UUID?
            let programName = r.text("program")
            if !programName.isEmpty {
                let sourceID = try r.uuid("program_id")
                let k = key(sourceID, programName)
                let id = programIDs[k] ?? sourceID ?? UUID(); programIDs[k] = id; programID = id
                let incoming = TrainingProgram(id: id, name: programName, notes: r.text("program_notes"))
                if let existing = data.program(id) { guard existing.name == incoming.name && existing.notes == incoming.notes else { throw TrainingError.invalid("Conflicting program details on row \(r.number).") } }
                else { data.programs.append(incoming) }
            } else if record == "program" { throw TrainingError.invalid("Missing program name on row \(r.number).") }
            if record == "program" { continue }
            let dayName = r.text("day"); try required(dayName, "day", r.number)
            let sourceDayID = try r.uuid("day_id")
            let dayKey = key(sourceDayID, "\(programID?.uuidString ?? "template")|\(dayName)")
            let dayID = dayIDs[dayKey] ?? sourceDayID ?? UUID(); dayIDs[dayKey] = dayID
            let incomingDay = Routine(id: dayID, name: dayName, notes: r.text("day_notes"))
            if let existing = data.routine(dayID) { guard existing.name == incomingDay.name && existing.notes == incomingDay.notes else { throw TrainingError.invalid("Conflicting day details on row \(r.number).") } }
            else { data.routines.append(incomingDay) }
            if let programID {
                let existingOrder = programOrder[programID]?.first { $0.value == dayID }?.key
                let order = try r.int("day_order", default: existingOrder ?? ((programOrder[programID]?.keys.max() ?? 0) + 1))!
                guard order > 0, programOrder[programID]?[order].map({ $0 == dayID }) ?? true else { throw TrainingError.invalid("Conflicting day order on row \(r.number).") }
                programOrder[programID, default: [:]][order] = dayID
            }
            if record == "day" { continue }
            let exerciseName = r.text("exercise"); try required(exerciseName, "exercise", r.number)
            guard let mode = ExerciseMode(rawValue: r.text("mode", default: "strength")) else { throw TrainingError.invalid("Invalid mode on row \(r.number).") }
            let sourceExerciseID = try r.uuid("exercise_id")
            let exerciseKey = key(sourceExerciseID, "\(exerciseName)|\(r.text("equipment"))|\(mode.rawValue)")
            let exerciseID = exerciseIDs[exerciseKey] ?? sourceExerciseID ?? UUID(); exerciseIDs[exerciseKey] = exerciseID
            let exercise = Exercise(id: exerciseID, name: exerciseName, muscle: r.text("muscle", default: "Other"), equipment: r.text("equipment"), mode: mode)
            if let existing = data.exercise(exerciseID) { guard existing == exercise else { throw TrainingError.invalid("Conflicting exercise details on row \(r.number).") } }
            else { data.exercises.append(exercise) }
            let sourceVariantID = try r.uuid("variant_id")
            let label = r.text("variant", default: [programName, dayName].filter { !$0.isEmpty }.joined(separator: " · "))
            let variantKey = key(sourceVariantID, "\(dayID)|\(exerciseID)|\(r.text("exercise_order"))|\(label)")
            let variantID = variantIDs[variantKey] ?? sourceVariantID ?? UUID(); variantIDs[variantKey] = variantID
            var progression = Progression()
            guard let progressionMode = ProgressionMode(rawValue: r.text("progression", default: "manual")) else { throw TrainingError.invalid("Invalid progression on row \(r.number).") }
            progression.mode = progressionMode
            progression.increment = try r.double("increment_kg", default: progression.increment)!
            progression.deloadAfter = try r.int("deload_after", default: progression.deloadAfter)!
            progression.deloadPercent = try r.double("deload_percent", default: progression.deloadPercent)!
            let variant = Variant(id: variantID, exerciseID: exerciseID, label: label, workingWeight: try r.double("working_weight_kg", default: 0)!, rounding: try r.double("rounding_kg", default: 0)!, restSeconds: try r.int("rest_seconds", default: 90)!, notes: r.text("exercise_notes"), sets: [], progression: progression)
            if var existing = data.variant(variantID) { existing.sets = []; guard existing == variant else { throw TrainingError.invalid("Conflicting variant details on row \(r.number).") } }
            else { data.variants.append(variant) }
            let existingExerciseOrder = slotOrder[dayID]?.first { $0.value.variantID == variantID }?.key
            let exerciseOrder = try r.int("exercise_order", default: existingExerciseOrder ?? ((slotOrder[dayID]?.keys.max() ?? 0) + 1))!
            guard exerciseOrder > 0, slotOrder[dayID]?[exerciseOrder].map({ $0.variantID == variantID && $0.group == r.text("group") }) ?? true else { throw TrainingError.invalid("Conflicting exercise order on row \(r.number).") }
            let slot = RoutineSlot(id: try r.uuid("slot_id") ?? slotOrder[dayID]?[exerciseOrder]?.id ?? UUID(), variantID: variantID, group: r.text("group"))
            slotOrder[dayID, default: [:]][exerciseOrder] = slot
            guard let kind = SetKind(rawValue: r.text("set_type", default: "working")), let load = LoadRule(rawValue: r.text("load_rule", default: mode == .strength ? "working" : "none")) else { throw TrainingError.invalid("Invalid set_type or load_rule on row \(r.number).") }
            let plan = SetPlan(id: try r.uuid("set_id") ?? UUID(), kind: kind, load: load, fixedWeight: try r.double("fixed_weight_kg", default: 0)!, percent: try r.double("percent", default: 50, maximum: 1000)!, reps: try r.int("reps_min"), repCeiling: try r.int("reps_max"), seconds: try r.double("seconds"), meters: try r.double("meters"), rpe: try r.double("rpe", maximum: 10), amrap: try r.bool("amrap"), restSeconds: try r.int("set_rest_seconds"))
            let position = try r.int("set_order", default: (setOrder[variantID]?.keys.max() ?? 0) + 1)!
            guard position > 0, setOrder[variantID]?[position].map({ $0 == plan }) ?? true else { throw TrainingError.invalid("Conflicting set order on row \(r.number).") }
            setOrder[variantID, default: [:]][position] = plan
        }
        for i in data.programs.indices { data.programs[i].dayIDs = (programOrder[data.programs[i].id] ?? [:]).sorted { $0.key < $1.key }.map(\.value) }
        for i in data.routines.indices { data.routines[i].slots = (slotOrder[data.routines[i].id] ?? [:]).sorted { $0.key < $1.key }.map(\.value) }
        for i in data.variants.indices { data.variants[i].sets = (setOrder[data.variants[i].id] ?? [:]).sorted { $0.key < $1.key }.map(\.value) }
        guard !data.programs.isEmpty || !data.routines.isEmpty else { throw TrainingError.invalid("The CSV has no programs or days.") }
        return RoutineBundle(content: try data.validated())
    }
}

public extension TrainingData {
    @discardableResult mutating func importRoutines(_ bundle: RoutineBundle, loadFirst: Bool = false) throws -> [UUID] {
        let source = try bundle.content.validated()
        guard source.sessions.isEmpty, source.activeSession == nil else { throw TrainingError.invalid("A routine CSV cannot contain workout history.") }
        var next = self
        var exerciseMap: [UUID: UUID] = [:], variantMap: [UUID: UUID] = [:], dayMap: [UUID: UUID] = [:], programMap: [UUID: UUID] = [:]
        for exercise in source.exercises {
            if let existing = next.exercises.first(where: { $0.name.caseInsensitiveCompare(exercise.name) == .orderedSame && $0.mode == exercise.mode && $0.equipment.caseInsensitiveCompare(exercise.equipment) == .orderedSame }) { exerciseMap[exercise.id] = existing.id }
            else { var copy = exercise; copy.id = UUID(); next.exercises.append(copy); exerciseMap[exercise.id] = copy.id }
        }
        for incoming in source.programs { programMap[incoming.id] = UUID() }
        for incoming in source.variants {
            var copy = incoming; copy.id = UUID(); copy.exerciseID = exerciseMap[incoming.exerciseID]!
            copy.label = Self.uniqueName(incoming.label, among: next.variants.filter { $0.exerciseID == copy.exerciseID }.map(\.label))
            copy.progression.failures = 0
            copy.sets = incoming.sets.map { value in var plan = value; plan.id = UUID(); return plan }
            next.variants.append(copy); variantMap[incoming.id] = copy.id
        }
        for incoming in source.routines {
            var copy = Routine(name: incoming.name, notes: incoming.notes)
            if source.programForDay(incoming.id) == nil { copy.name = Self.uniqueName(copy.name, among: next.dayTemplates.map(\.name)) }
            copy.slots = incoming.slots.map { RoutineSlot(variantID: variantMap[$0.variantID]!, group: $0.group) }
            next.routines.append(copy); dayMap[incoming.id] = copy.id
        }
        var imported: [UUID] = []
        for incoming in source.programs {
            let id = programMap[incoming.id]!
            let copy = TrainingProgram(id: id, name: Self.uniqueName(incoming.name, among: next.programs.map(\.name)), notes: incoming.notes, dayIDs: incoming.dayIDs.map { dayMap[$0]! })
            next.programs.append(copy); imported.append(id)
        }
        if loadFirst, let first = imported.first { next.activeProgramID = first }
        self = try next.validated()
        return imported
    }
}
