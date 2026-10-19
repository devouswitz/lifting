import Foundation

/// A user-named set type. It behaves like one of the built-in kinds it counts as
/// (working, warm-up, or failure), so volume, progression, and warm-up handling stay unchanged;
/// the name, badge, and color are how it reads in tables and history.
public struct CustomSetType: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var badge: String
    /// Hex color such as "#FF9500". Nil uses the Drop and MYO color role.
    public var color: String?
    public var countsAs: SetKind
    public init(id: UUID = UUID(), name: String, badge: String, color: String? = nil, countsAs: SetKind = .working) {
        self.id = id; self.name = name; self.badge = badge; self.color = color; self.countsAs = countsAs
    }
    public static let baseKinds: [SetKind] = [.working, .warmup, .failure]
    public var isValid: Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mark = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean.count <= 40 && (1...3).contains(mark.count) && Self.baseKinds.contains(countsAs)
            && (color.map { ColorTheme.parse($0) != nil } ?? true)
    }
    /// A default badge from the name's first letter, avoiding built-in letters where possible.
    public static func suggestedBadge(for name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

public extension TrainingData {
    func setType(_ id: UUID?) -> CustomSetType? { id.flatMap { id in customSetTypes.first { $0.id == id } } }

    /// Display name for a set: its custom type when one is assigned, otherwise the built-in kind.
    func setTypeTitle(_ plan: SetPlan) -> String { setType(plan.customTypeID)?.name ?? plan.kind.title }

    /// Saves a custom type. Changing what it counts as also updates saved prescriptions and pending
    /// sets in the active workout that use it; finished history keeps what it recorded.
    mutating func saveSetType(_ value: CustomSetType) throws {
        var type = value
        type.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        type.badge = type.badge.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard type.isValid else { throw TrainingError.invalid("Name the set type, give it a 1-3 character badge, and choose what it counts as.") }
        guard !customSetTypes.contains(where: { $0.id != type.id && $0.name.caseInsensitiveCompare(type.name) == .orderedSame }),
              !SetKind.allCases.contains(where: { $0.title.caseInsensitiveCompare(type.name) == .orderedSame }) else { throw TrainingError.invalid("A set type with that name already exists.") }
        if let index = customSetTypes.firstIndex(where: { $0.id == type.id }) { customSetTypes[index] = type } else { customSetTypes.append(type) }
        for v in variants.indices { for s in variants[v].sets.indices where variants[v].sets[s].customTypeID == type.id { variants[v].sets[s].kind = type.countsAs } }
        for e in (activeSession?.exercises.indices ?? 0..<0) {
            for s in activeSession!.exercises[e].sets.indices where activeSession!.exercises[e].sets[s].plan.customTypeID == type.id && activeSession!.exercises[e].sets[s].completedAt == nil {
                activeSession!.exercises[e].sets[s].plan.kind = type.countsAs
            }
        }
        _ = try validated()
    }

    /// Removes a custom type. Sets that used it keep what they counted as and show that built-in name.
    mutating func removeSetType(_ id: UUID) {
        customSetTypes.removeAll { $0.id == id }
        for v in variants.indices { for s in variants[v].sets.indices where variants[v].sets[s].customTypeID == id { variants[v].sets[s].customTypeID = nil } }
        for e in (activeSession?.exercises.indices ?? 0..<0) {
            for s in activeSession!.exercises[e].sets.indices where activeSession!.exercises[e].sets[s].plan.customTypeID == id { activeSession!.exercises[e].sets[s].plan.customTypeID = nil }
        }
    }

    /// Adds a set of a given kind or custom type to a live exercise, copying the last work set's targets.
    mutating func addTypedSet(to exerciseID: UUID, kind: SetKind, customTypeID: UUID? = nil) throws {
        guard let e = activeSession?.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw TrainingError.invalid("Exercise unavailable.") }
        let resolved = setType(customTypeID)?.countsAs ?? kind
        if resolved == .warmup {
            try addSessionSet(to: exerciseID, warmup: true)
            let last = activeSession!.exercises[e].sets.indices.last!
            activeSession!.exercises[e].sets[last].plan.customTypeID = customTypeID
            return
        }
        guard let variant = variant(activeSession!.exercises[e].variantID) else { throw TrainingError.invalid("Exercise unavailable.") }
        let item = activeSession!.exercises[e]
        let source = item.sets.last(where: { [.working, .failure].contains($0.plan.kind) })
        var set = source ?? item.sets.last ?? LoggedSet(plan: SetPlan(), variant: variant)
        let fromTechnique = source == nil && [.drop, .myoActivation, .myoMini, .warmup].contains(set.plan.kind)
        set.id = UUID(); set.plan.id = UUID(); set.completedAt = nil
        set.plan.kind = resolved; set.plan.customTypeID = customTypeID
        if fromTechnique {
            set.plan.load = item.mode == .strength ? .working : .none
            set.weight = set.plan.resolvedWeight(working: item.workingLoad(fallback: variant.workingWeight), increment: item.roundingIncrement ?? variant.rounding)
        }
        set.plan.restSeconds = nil
        if set.plan.repRange != nil || set.plan.reps == nil { set.reps = nil } else { set.reps = set.plan.reps }
        activeSession!.exercises[e].sets.append(set)
    }

    /// Copies custom types referenced by imported records, matching existing types by name,
    /// and points the newly added prescriptions and sessions at the local types.
    mutating func adoptSetTypes(from source: TrainingData, existingVariants: Set<UUID>, existingSessions: Set<UUID>) {
        var map: [UUID: UUID] = [:]
        for type in source.customSetTypes {
            if let match = customSetTypes.first(where: { $0.name.caseInsensitiveCompare(type.name) == .orderedSame }) { map[type.id] = match.id }
            else { var copy = type; copy.id = UUID(); customSetTypes.append(copy); map[type.id] = copy.id }
        }
        guard !map.isEmpty else { return }
        for v in variants.indices where !existingVariants.contains(variants[v].id) {
            for s in variants[v].sets.indices { if let id = variants[v].sets[s].customTypeID { variants[v].sets[s].customTypeID = map[id] } }
        }
        for i in sessions.indices where !existingSessions.contains(sessions[i].id) {
            for e in sessions[i].exercises.indices { for s in sessions[i].exercises[e].sets.indices {
                if let id = sessions[i].exercises[e].sets[s].plan.customTypeID { sessions[i].exercises[e].sets[s].plan.customTypeID = map[id] }
            } }
        }
    }

    /// Finds or creates a custom type for a CSV row's set type name.
    mutating func csvSetType(name: String, badge: String, color: String, countsAs kind: SetKind) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.caseInsensitiveCompare(kind.title) != .orderedSame else { return nil }
        if let match = customSetTypes.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { return match.id }
        let type = CustomSetType(name: String(clean.prefix(40)), badge: badge.isEmpty ? CustomSetType.suggestedBadge(for: clean) : String(badge.prefix(3)).uppercased(),
                                 color: ColorTheme.parse(color) == nil ? nil : color, countsAs: CustomSetType.baseKinds.contains(kind) ? kind : .working)
        customSetTypes.append(type)
        return type.id
    }
}
