import Foundation
import CryptoKit

public struct HistoryBundle: Sendable {
    public var content: TrainingData
    public var warnings: [String]
    public init(content: TrainingData, warnings: [String] = []) { self.content = content; self.warnings = warnings }
}

public enum HistoryCSV {
    public static let headers = ["date", "workout", "exercise", "variant", "variant_id", "kind", "weight_kg", "reps", "seconds", "meters", "rpe", "notes", "session_id", "ended_at", "workout_notes", "exercise_id", "mode", "muscle", "equipment", "session_exercise_id", "set_id", "recurring_notes", "rest_seconds", "exercise_rest_seconds", "completed_at", "program_id", "program_name", "target_reps", "target_rep_ceiling", "group", "group_rest_seconds", "transition_seconds", "secondary_muscles", "source_fields", "set_type_name", "set_type_badge"]
    public static func export(_ data: TrainingData) -> Data {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [headers]
        for session in data.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in session.exercises {
                for set in exercise.sets where set.completedAt != nil {
                    var row: [String] = [format.string(from: session.startedAt), session.name, exercise.name, exercise.label, exercise.variantID.uuidString, set.plan.kind.rawValue]
                    row += [set.weight.map { String($0) } ?? "", set.reps.map { String($0) } ?? "", set.seconds.map { String($0) } ?? "", set.meters.map { String($0) } ?? "", set.rpe.map { String($0) } ?? "", exercise.notes]
                    row += [session.id.uuidString, session.endedAt.map(format.string) ?? "", session.notes, exercise.exerciseID.uuidString, exercise.mode.rawValue, exercise.muscle ?? data.exercise(exercise.exerciseID)?.muscle ?? "", data.exercise(exercise.exerciseID)?.equipment ?? "", exercise.id.uuidString, set.id.uuidString, exercise.recurringNotes]
                    row += [set.plan.restSeconds.map { String($0) } ?? "", String(exercise.restSeconds), set.completedAt.map(format.string) ?? ""]
                    row += [session.programID?.uuidString ?? "", session.programName ?? session.programID.flatMap(data.program)?.name ?? "", set.plan.reps.map(String.init) ?? "", set.plan.repCeiling.map(String.init) ?? ""]
                    let sourceFields = set.sourceFields.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    row += [exercise.group ?? "", exercise.groupRestSeconds.map(String.init) ?? "", exercise.transitionSeconds.map(String.init) ?? "", exercise.secondaryMuscles?.joined(separator: "|") ?? "", sourceFields]
                    row += [data.setType(set.plan.customTypeID)?.name ?? "", data.setType(set.plan.customTypeID)?.badge ?? ""]
                    rows.append(row)
                }
            }
        }
        return CSVCodec.render(rows)
    }

    public static func decode(_ bytes: Data) throws -> HistoryBundle {
        let table = try CSVCodec.parse(bytes)
        let header = table[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_") }
        guard Set(header).count == header.count, ["date", "workout", "exercise", "weight_kg"].allSatisfy(header.contains) else { throw TrainingError.invalid("Use a Lifting day/program CSV or logged-set CSV with date, workout, exercise, and weight_kg columns.") }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: String, row: Int) throws -> Date {
            guard let date = fractional.date(from: value) ?? formatter.date(from: value) else { throw TrainingError.invalid("Invalid date on CSV row \(row).") }
            return date
        }
        let rows = table.dropFirst().enumerated().map { CSVRow(values: Dictionary(uniqueKeysWithValues: zip(header, $0.element)), number: $0.offset + 2) }
        var modes: [String: ExerciseMode] = [:]
        for row in rows {
            let name = row.text("exercise")
            if !row.text("weight_kg").isEmpty { modes[name] = .strength }
            else if modes[name] != .strength, !row.text("seconds").isEmpty || !row.text("meters").isEmpty { modes[name] = .cardio }
            else if modes[name] == nil { modes[name] = .bodyweight }
        }
        var data = TrainingData()
        for r in rows {
            let name = r.text("exercise"), workout = r.text("workout")
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !workout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrainingError.invalid("Missing exercise or workout on row \(r.number).") }
            let started = try date(r.text("date"), row: r.number)
            let ended = r.text("ended_at").isEmpty ? started : try date(r.text("ended_at"), row: r.number)
            let sessionID = try r.uuid("session_id") ?? stableID("session|\(r.text("date"))|\(workout)")
            let mode: ExerciseMode
            if r.text("mode").isEmpty { mode = modes[name] ?? .strength }
            else { guard let parsed = ExerciseMode(rawValue: r.text("mode")) else { throw TrainingError.invalid("Invalid mode on row \(r.number).") }; mode = parsed }
            let exerciseID = try r.uuid("exercise_id") ?? stableID("exercise|\(name)|\(r.text("equipment"))")
            if data.exercise(exerciseID) == nil { data.exercises.append(Exercise(id: exerciseID, name: name, muscle: r.text("muscle", default: "Other"), equipment: r.text("equipment"), mode: mode)) }
            let label = r.text("variant").isEmpty ? workout : r.text("variant")
            let variantID = try r.uuid("variant_id") ?? stableID("variant|\(exerciseID)|\(label)")
            if let existing = data.variant(variantID) { guard existing.exerciseID == exerciseID else { throw TrainingError.invalid("Conflicting variant on row \(r.number).") } }
            else { data.variants.append(Variant(id: variantID, exerciseID: exerciseID, label: label, restSeconds: try r.int("exercise_rest_seconds", default: 90)!, notes: r.text("recurring_notes"), sets: [])) }
            let programID = try r.uuid("program_id")
            let programName = r.text("program_name").isEmpty ? nil : r.text("program_name")
            if let existing = data.sessions.first(where: { $0.id == sessionID }) {
                guard existing.name == workout, existing.startedAt == started, existing.endedAt == ended, existing.notes == r.text("workout_notes"), existing.programID == programID, existing.programName == programName else { throw TrainingError.invalid("Conflicting workout details on row \(r.number).") }
            } else {
                var session = Session(id: sessionID, name: workout, startedAt: started, endedAt: ended); session.notes = r.text("workout_notes"); session.programID = programID; session.programName = programName; data.sessions.append(session)
            }
            let s = data.sessions.firstIndex { $0.id == sessionID }!
            let sessionExerciseID = try r.uuid("session_exercise_id") ?? stableID("session-exercise|\(sessionID)|\(variantID)")
            if let existing = data.sessions[s].exercises.first(where: { $0.id == sessionExerciseID }) {
                guard existing.exerciseID == exerciseID, existing.variantID == variantID, existing.name == name, existing.notes == r.text("notes"), existing.recurringNotes == r.text("recurring_notes") else { throw TrainingError.invalid("Conflicting exercise details on row \(r.number).") }
            } else {
                var item = SessionExercise(variant: data.variant(variantID)!, exercise: data.exercise(exerciseID)!)
                item.id = sessionExerciseID; item.name = name; item.mode = mode; item.label = label; item.notes = r.text("notes"); item.sets = []
                item.group = r.text("group").isEmpty ? nil : r.text("group"); item.groupRestSeconds = try r.int("group_rest_seconds"); item.transitionSeconds = try r.int("transition_seconds")
                item.muscle = r.text("muscle", default: "Other"); item.secondaryMuscles = r.text("secondary_muscles").isEmpty ? nil : r.text("secondary_muscles").components(separatedBy: "|")
                data.sessions[s].exercises.append(item)
            }
            let e = data.sessions[s].exercises.firstIndex { $0.id == sessionExerciseID }!
            guard let kind = SetKind(rawValue: r.text("kind", default: "working")) else { throw TrainingError.invalid("Invalid kind on row \(r.number).") }
            let weight = try r.double("weight_kg"), reps = try r.int("reps")
            let targetReps = header.contains("target_reps") ? try r.int("target_reps") : reps
            let plan = SetPlan(kind: kind, load: weight == nil ? .none : .fixed, fixedWeight: weight ?? 0, reps: targetReps, repCeiling: try r.int("target_rep_ceiling"), seconds: try r.double("seconds"), meters: try r.double("meters"), rpe: try r.double("rpe", maximum: 10), restSeconds: try r.int("rest_seconds"))
            var typedPlan = plan
            typedPlan.customTypeID = data.csvSetType(name: r.text("set_type_name"), badge: r.text("set_type_badge"), color: "", countsAs: kind)
            var logged = LoggedSet(plan: typedPlan, variant: data.variant(variantID)!)
            logged.reps = reps
            if !r.text("source_fields").isEmpty {
                logged.sourceFields = try JSONDecoder().decode([String: String].self, from: Data(r.text("source_fields").utf8))
            }
            logged.id = try r.uuid("set_id") ?? stableID("set|\(sessionExerciseID)|\(data.sessions[s].exercises[e].sets.count)")
            logged.completedAt = r.text("completed_at").isEmpty ? started : try date(r.text("completed_at"), row: r.number)
            data.sessions[s].exercises[e].sets.append(logged)
        }
        for v in data.variants.indices {
            let id = data.variants[v].id
            data.variants[v].sets = data.sessions.flatMap(\.exercises).first(where: { $0.variantID == id })?.sets.map(\.plan) ?? []
        }
        guard !data.sessions.isEmpty else { throw TrainingError.invalid("The CSV has no logged sets.") }
        let warnings = header.contains("ended_at") ? [] : ["Legacy CSV has no workout duration. Exercise types were inferred."]
        return HistoryBundle(content: try data.validated(), warnings: warnings)
    }

    private static func stableID(_ text: String) -> UUID {
        let b = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

public extension TrainingData {
    mutating func createProgramFromHistory(_ bundle: HistoryBundle, name: String) throws {
        let programID = try createProgram(name: name)
        let latest = Dictionary(grouping: bundle.content.sessions, by: { "\($0.programName ?? "")|\($0.name)" }).values.compactMap { $0.max { $0.startedAt < $1.startedAt } }.sorted { $0.name < $1.name }
        var dayMap: [String: UUID] = [:]
        for session in latest {
            let existingNames = program(programID)!.dayIDs.compactMap(routine).map(\.name)
            let dayID = try addDay(to: programID, name: Self.uniqueName(session.name, among: existingNames))
            dayMap["\(session.programName ?? "")|\(session.name)"] = dayID
            let r = routines.firstIndex { $0.id == dayID }!
            routines[r].notes = session.notes
            for item in session.exercises {
                let mapped = historyImports.first(where: { $0.sourceVariantID == item.variantID })?.variantID ?? item.variantID
                guard let v = variant(mapped) else { throw TrainingError.invalid("Import the workout history before building its program.") }
                if let index = variants.firstIndex(where: { $0.id == v.id }) {
                    let base = item.sets.first(where: { $0.plan.kind == .working || $0.plan.kind == .failure || $0.plan.kind == .myoActivation })?.weight ?? item.sets.first(where: { $0.plan.kind != .warmup })?.weight ?? 0
                    variants[index].workingWeight = base
                    variants[index].sets = item.sets.map { logged in
                        var plan = logged.plan; plan.id = UUID()
                        if let weight = logged.weight, base > 0, plan.load == .fixed {
                            if plan.kind == .warmup || plan.kind == .drop { plan.load = .percent; plan.percent = weight / base * 100 }
                            else if abs(weight - base) < 0.000001 { plan.load = .working }
                        }
                        return plan
                    }
                    for s in variants[index].sets.indices.dropLast() where variants[index].sets[s + 1].kind == .drop { variants[index].sets[s].restSeconds = 0 }
                }
                var slot = RoutineSlot(variantID: v.id, group: item.group ?? "")
                slot.groupRestSeconds = item.groupRestSeconds; slot.transitionSeconds = item.transitionSeconds
                routines[r].slots.append(slot)
            }
        }
        let sourceSessions = Dictionary(uniqueKeysWithValues: bundle.content.sessions.map { ($0.id, $0) })
        for s in sessions.indices {
            guard let source = sourceSessions[sessions[s].id] else { continue }
            sessions[s].routineID = dayMap["\(source.programName ?? "")|\(source.name)"]
            sessions[s].programID = programID; sessions[s].programName = program(programID)?.name
        }
        activeProgramID = programID
    }
    @discardableResult mutating func importHistory(_ bundle: HistoryBundle) throws -> Int {
        let source = try bundle.content.validated()
        let known = Set(sessions.map(\.id))
        let incoming = source.sessions.filter { !known.contains($0.id) }
        guard !incoming.isEmpty else { return 0 }
        var next = self
        let priorVariants = Set(next.variants.map(\.id)), priorSessions = Set(next.sessions.map(\.id))
        // Recover identities for CSVs imported before import links were stored.
        let existingSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        for session in source.sessions where known.contains(session.id) {
            guard let existing = existingSessions[session.id] else { continue }
            for item in session.exercises {
                guard !next.historyImports.contains(where: { $0.sourceVariantID == item.variantID }),
                      let old = existing.exercises.first(where: { $0.id == item.id }) else { continue }
                next.historyImports.append(HistoryImportLink(sourceVariantID: item.variantID, variantID: old.variantID, sourceExerciseID: item.exerciseID, exerciseID: old.exerciseID))
            }
        }
        let neededVariants = Set(incoming.flatMap(\.exercises).map(\.variantID))
        let neededExercises = Set(incoming.flatMap(\.exercises).map(\.exerciseID))
        var exerciseMap: [UUID: UUID] = [:], variantMap: [UUID: UUID] = [:]
        for exercise in source.exercises where neededExercises.contains(exercise.id) {
            let linkedID = next.historyImports.first(where: { $0.sourceExerciseID == exercise.id })?.exerciseID
            if let existing = linkedID.flatMap(next.exercise) ?? next.exercise(exercise.id) ?? ExerciseMatching.match(exercise, among: next.exercises) { exerciseMap[exercise.id] = existing.id }
            else { var copy = exercise; copy.id = UUID(); next.exercises.append(copy); exerciseMap[exercise.id] = copy.id }
        }
        for variant in source.variants where neededVariants.contains(variant.id) {
            let link = next.historyImports.first { $0.sourceVariantID == variant.id }
            if let link {
                guard link.sourceExerciseID == variant.exerciseID, link.exerciseID == exerciseMap[variant.exerciseID] else { throw TrainingError.invalid("An imported track refers to a different exercise than its previous import.") }
                variantMap[variant.id] = link.variantID
            }
            else if let existing = next.variant(variant.id), existing.exerciseID == exerciseMap[variant.exerciseID] { variantMap[variant.id] = existing.id }
            else {
                var copy = variant; copy.id = UUID(); copy.exerciseID = exerciseMap[variant.exerciseID]!
                copy.substitutionSourceID = nil
                copy.label = Self.uniqueName(copy.label, among: next.variants.filter { $0.exerciseID == copy.exerciseID }.map(\.label))
                copy.sets = copy.sets.map { value in var plan = value; plan.id = UUID(); return plan }
                next.variants.append(copy); variantMap[variant.id] = copy.id
            }
            if link == nil { next.historyImports.append(HistoryImportLink(sourceVariantID: variant.id, variantID: variantMap[variant.id]!, sourceExerciseID: variant.exerciseID, exerciseID: exerciseMap[variant.exerciseID]!)) }
        }
        for var session in incoming {
            session.routineID = nil; session.advancesProgram = nil
            for e in session.exercises.indices {
                session.exercises[e].exerciseID = exerciseMap[session.exercises[e].exerciseID]!; session.exercises[e].variantID = variantMap[session.exercises[e].variantID]!
                if session.exercises[e].muscle?.lowercased() == "other" { session.exercises[e].muscle = nil }
            }
            next.sessions.append(session)
        }
        next.sessions.sort { $0.startedAt < $1.startedAt }
        next.adoptSetTypes(from: source, existingVariants: priorVariants, existingSessions: priorSessions)
        self = try next.validated()
        return incoming.count
    }
}
