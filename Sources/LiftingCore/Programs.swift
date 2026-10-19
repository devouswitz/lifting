import Foundation

public struct TrainingProgram: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var dayIDs: [UUID]
    public var nextDayIndex: Int
    public init(id: UUID = UUID(), name: String, notes: String = "", dayIDs: [UUID] = [], nextDayIndex: Int = 0) {
        self.id = id; self.name = name; self.notes = notes; self.dayIDs = dayIDs; self.nextDayIndex = nextDayIndex
    }
    public var nextDayID: UUID? { dayIDs.indices.contains(nextDayIndex) ? dayIDs[nextDayIndex] : dayIDs.first }
}

public extension TrainingData {
    func program(_ id: UUID) -> TrainingProgram? { programs.first { $0.id == id } }
    func routine(_ id: UUID) -> Routine? { routines.first { $0.id == id } }
    var activeProgram: TrainingProgram? { activeProgramID.flatMap(program) }
    var dayTemplates: [Routine] {
        let owned = Set(programs.flatMap(\.dayIDs))
        return routines.filter { !owned.contains($0.id) }
    }
    func programForDay(_ dayID: UUID) -> TrainingProgram? { programs.first { $0.dayIDs.contains(dayID) } }

    @discardableResult mutating func createProgram(name: String, templateIDs: [UUID] = []) throws -> UUID {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200 else { throw TrainingError.invalid("Enter a program name.") }
        guard templateIDs.allSatisfy({ routine($0) != nil }) else { throw TrainingError.invalid("A selected template is unavailable.") }
        let unique = Self.uniqueName(clean, among: programs.map(\.name))
        var program = TrainingProgram(name: unique)
        for id in templateIDs { program.dayIDs.append(try copyDay(id, context: unique).id) }
        programs.append(program)
        return program.id
    }

    @discardableResult mutating func addDay(to programID: UUID, templateID: UUID? = nil, name: String? = nil) throws -> UUID {
        guard let p = programs.firstIndex(where: { $0.id == programID }) else { throw TrainingError.invalid("Program unavailable.") }
        let day: Routine
        if let templateID { day = try copyDay(templateID, name: name, context: programs[p].name) }
        else {
            let clean = (name ?? "New day").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw TrainingError.invalid("Enter a day name.") }
            day = Routine(name: clean); routines.append(day)
        }
        programs[p].dayIDs.append(day.id)
        return day.id
    }

    @discardableResult mutating func saveDayAsTemplate(_ dayID: UUID, name: String? = nil) throws -> UUID {
        guard let day = routine(dayID) else { throw TrainingError.invalid("Day unavailable.") }
        return try copyDay(dayID, name: Self.uniqueName(name ?? day.name, among: dayTemplates.map(\.name))).id
    }

    @discardableResult mutating func duplicateProgram(_ id: UUID) throws -> UUID {
        guard let source = program(id) else { throw TrainingError.invalid("Program unavailable.") }
        let copyID = try createProgram(name: Self.uniqueName(source.name + " copy", among: programs.map(\.name)), templateIDs: source.dayIDs)
        if let index = programs.firstIndex(where: { $0.id == copyID }) { programs[index].notes = source.notes }
        return copyID
    }

    mutating func loadProgram(_ id: UUID) throws {
        guard program(id) != nil else { throw TrainingError.invalid("Program unavailable.") }
        activeProgramID = id
    }

    mutating func selectNextDay(_ dayID: UUID, in programID: UUID) throws {
        guard let p = programs.firstIndex(where: { $0.id == programID }), let index = programs[p].dayIDs.firstIndex(of: dayID) else { throw TrainingError.invalid("Day unavailable.") }
        programs[p].nextDayIndex = index
    }

    mutating func reorderDays(_ ids: [UUID], in programID: UUID) throws {
        guard let p = programs.firstIndex(where: { $0.id == programID }), ids.count == programs[p].dayIDs.count, Set(ids) == Set(programs[p].dayIDs) else { throw TrainingError.invalid("The day order is invalid.") }
        let next = programs[p].nextDayID
        programs[p].dayIDs = ids
        programs[p].nextDayIndex = next.flatMap { ids.firstIndex(of: $0) } ?? 0
    }

    /// The program's days in the order they come up, starting with the next day and wrapping.
    func upcomingDays(_ programID: UUID) -> [UUID] {
        guard let program = program(programID), let start = program.nextDayID.flatMap(program.dayIDs.firstIndex) else { return [] }
        return Array(program.dayIDs[start...] + program.dayIDs[..<start])
    }

    /// Moves a day one place earlier or later in the upcoming order. The next workout is a position
    /// in the rotation, so moving the next day later makes the following day next.
    mutating func moveUpcomingDay(_ dayID: UUID, by delta: Int, in programID: UUID) throws {
        guard let p = programs.firstIndex(where: { $0.id == programID }), let start = programs[p].nextDayID.flatMap(programs[p].dayIDs.firstIndex) else { throw TrainingError.invalid("Program unavailable.") }
        var queue = upcomingDays(programID)
        guard let i = queue.firstIndex(of: dayID), queue.indices.contains(i + delta) else { throw TrainingError.invalid("That day cannot move further.") }
        queue.swapAt(i, i + delta)
        let count = queue.count
        var ids = programs[p].dayIDs
        for k in 0..<count { ids[(start + k) % count] = queue[k] }
        programs[p].dayIDs = ids
        programs[p].nextDayIndex = start
    }

    /// Reorders day templates; program days keep their own order.
    mutating func reorderTemplates(_ ids: [UUID]) throws {
        guard Set(ids) == Set(dayTemplates.map(\.id)), ids.count == dayTemplates.count else { throw TrainingError.invalid("The template order is invalid.") }
        routines = routines.filter { !ids.contains($0.id) } + ids.compactMap(routine)
    }

    /// Records the program's next day as skipped (every set unchecked) and moves Next to the following day.
    mutating func skipNextDay(in programID: UUID, now: Date = Date()) throws {
        guard let p = programs.firstIndex(where: { $0.id == programID }), let dayID = programs[p].nextDayID,
              let day = routine(dayID), let index = programs[p].dayIDs.firstIndex(of: dayID) else { throw TrainingError.invalid("There is no next workout to skip.") }
        guard activeSession?.routineID != dayID else { throw TrainingError.invalid("Finish or discard this workout before skipping it.") }
        var session = Session(routineID: dayID, name: day.name, startedAt: now, endedAt: now)
        session.exercises = try day.slots.map { slot in
            guard let variant = variant(slot.variantID), let exercise = exercise(variant.exerciseID) else { throw TrainingError.invalid("An exercise is missing.") }
            var item = SessionExercise(variant: variant, exercise: exercise, slotID: slot.id)
            item.group = slot.group.isEmpty ? nil : slot.group; item.progressionEligible = false
            return item
        }
        session.programID = programID; session.programName = programs[p].name; session.skipped = true; session.notes = day.notes
        sessions.append(session)
        programs[p].nextDayIndex = (index + 1) % programs[p].dayIDs.count
    }

    mutating func removeDay(_ dayID: UUID) {
        for p in programs.indices where programs[p].dayIDs.contains(dayID) {
            let next = programs[p].nextDayID
            let oldIndex = programs[p].nextDayIndex
            programs[p].dayIDs.removeAll { $0 == dayID }
            programs[p].nextDayIndex = next.flatMap { programs[p].dayIDs.firstIndex(of: $0) } ?? (programs[p].dayIDs.isEmpty ? 0 : oldIndex % programs[p].dayIDs.count)
        }
        routines.removeAll { $0.id == dayID }
    }

    mutating func removeProgram(_ id: UUID) {
        let owned = Set(program(id)?.dayIDs ?? [])
        programs.removeAll { $0.id == id }
        routines.removeAll { owned.contains($0.id) }
        if activeProgramID == id { activeProgramID = programs.first?.id }
    }

    static func uniqueName(_ base: String, among values: [String]) -> String {
        let clean = String(base.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let taken = Set(values.map { $0.lowercased() })
        if !taken.contains(clean.lowercased()) { return clean }
        var count = 2
        while true {
            let suffix = " (\(count))"
            let candidate = String(clean.prefix(200 - suffix.count)) + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
            count += 1
        }
    }

    private mutating func copyDay(_ id: UUID, name: String? = nil, context: String? = nil) throws -> Routine {
        guard let source = routine(id) else { throw TrainingError.invalid("Day unavailable.") }
        let clean = (name ?? source.name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TrainingError.invalid("Enter a day name.") }
        var copy = Routine(name: clean, notes: source.notes)
        for slot in source.slots {
            guard var variant = variant(slot.variantID) else { throw TrainingError.invalid("Exercise unavailable.") }
            variant.id = UUID()
            variant.substitutionSourceID = nil
            let base = [context, clean].compactMap { $0 }.joined(separator: " · ")
            variant.label = Self.uniqueName(base, among: variants.filter { $0.exerciseID == variant.exerciseID }.map(\.label))
            variant.progression.failures = 0
            variant.sets = variant.sets.map { plan in var p = plan; p.id = UUID(); return p }
            var linkedSlot = slot; linkedSlot.id = UUID(); linkedSlot.variantID = variant.id
            variants.append(variant); copy.slots.append(linkedSlot)
        }
        routines.append(copy)
        return copy
    }
}

public struct RecordedProgram: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
}

public extension TrainingData {
    var recordedPrograms: [RecordedProgram] {
        var names = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0.name) })
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            if let id = session.programID, names[id] == nil { names[id] = session.programName ?? "Archived program" }
        }
        return names.map { RecordedProgram(id: $0.key, name: $0.value) }.sorted {
            $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func sessions(inProgram id: UUID?) -> [Session] {
        guard let id else { return sessions }
        let days = Set(program(id)?.dayIDs ?? [])
        return sessions.filter { $0.programID == id || ($0.programID == nil && $0.routineID.map(days.contains) == true) }
    }
    func title(for session: Session) -> String {
        let name = session.programName ?? session.programID.flatMap(program)?.name ?? session.routineID.flatMap(programForDay)?.name
        return name.map { "\($0) - \(session.name)" } ?? session.name
    }
}
