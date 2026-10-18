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
            let base = [context, clean].compactMap { $0 }.joined(separator: " · ")
            variant.label = Self.uniqueName(base, among: variants.filter { $0.exerciseID == variant.exerciseID }.map(\.label))
            variant.progression.failures = 0
            variant.sets = variant.sets.map { plan in var p = plan; p.id = UUID(); return p }
            variants.append(variant); copy.slots.append(RoutineSlot(variantID: variant.id, group: slot.group))
        }
        routines.append(copy)
        return copy
    }
}
