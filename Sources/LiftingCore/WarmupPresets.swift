import Foundation

public struct WarmupPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sets: [SetPlan]
    public init(id: UUID = UUID(), name: String, sets: [SetPlan]) { self.id = id; self.name = name; self.sets = sets }
    /// The built-in preset offered before any are saved. Its id is fixed so the last-applied preset can be recognized.
    public static let standard = WarmupPreset(id: UUID(uuidString: "5E7F0A11-0000-4000-8000-000000000001")!, name: "Standard",
        sets: [(50.0, 8), (70.0, 5), (85.0, 2)].map { SetPlan(kind: .warmup, load: .percent, percent: $0.0, reps: $0.1, repCeiling: nil) })
}

public extension TrainingData {
    mutating func saveWarmupPreset(_ preset: WarmupPreset) throws {
        var copy = preset
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sets = Self.warmupCopies(copy.sets)
        guard !copy.name.isEmpty, copy.name.count <= 200, !copy.sets.isEmpty else { throw TrainingError.invalid("Name the warm-up preset and add a set.") }
        if let index = warmupPresets.firstIndex(where: { $0.id == copy.id }) { warmupPresets[index] = copy }
        else { warmupPresets.append(copy) }
        _ = try validated()
    }
    static func warmupCopies(_ plans: [SetPlan]) -> [SetPlan] {
        plans.map { value in var plan = value; plan.id = UUID(); plan.kind = .warmup; return plan }
    }
    static func applyingWarmups(_ plans: [SetPlan], to existing: [SetPlan], replacing: Bool) -> [SetPlan] {
        let warmups = (replacing ? [] : existing.filter { $0.kind == .warmup }) + warmupCopies(plans)
        return warmups + existing.filter { $0.kind != .warmup }
    }
    mutating func applyWarmupPreset(_ id: UUID, toVariants ids: Set<UUID>, replacing: Bool = true) throws {
        guard let preset = warmupPresets.first(where: { $0.id == id }) else { throw TrainingError.invalid("Choose a warm-up preset.") }
        try applyWarmups(preset.sets, toVariants: ids, replacing: replacing)
    }
    mutating func applyWarmups(_ plans: [SetPlan], toVariants ids: Set<UUID>, replacing: Bool = true) throws {
        guard !plans.isEmpty, plans.allSatisfy(\.isValid), !ids.isEmpty, ids.allSatisfy({ variant($0) != nil }) else { throw TrainingError.invalid("Choose valid warm-ups and exercises.") }
        for v in variants.indices where ids.contains(variants[v].id) { variants[v].sets = Self.applyingWarmups(plans, to: variants[v].sets, replacing: replacing) }
    }
    mutating func applyWarmupPreset(_ id: UUID, toSessionExercises ids: Set<UUID>, replacing: Bool = true, saveFuture: Bool = false) throws {
        guard let preset = warmupPresets.first(where: { $0.id == id }) else { throw TrainingError.invalid("Choose a warm-up preset.") }
        try applyWarmups(preset.sets, toSessionExercises: ids, replacing: replacing, saveFuture: saveFuture)
    }
    mutating func applyWarmups(_ plans: [SetPlan], toSessionExercises ids: Set<UUID>, replacing: Bool = true, saveFuture: Bool = false) throws {
        guard !plans.isEmpty, plans.allSatisfy(\.isValid), let session = activeSession, !ids.isEmpty, ids.isSubset(of: Set(session.exercises.map(\.id))) else { throw TrainingError.invalid("Choose valid warm-ups and exercises.") }
        for e in activeSession!.exercises.indices where ids.contains(activeSession!.exercises[e].id) {
            let item = activeSession!.exercises[e]
            guard var variant = variant(item.variantID) else { throw TrainingError.invalid("Exercise unavailable.") }
            variant.workingWeight = item.workingLoad(fallback: variant.workingWeight); variant.rounding = item.roundingIncrement ?? variant.rounding
            let copies = Self.warmupCopies(plans)
            if replacing { activeSession!.exercises[e].sets.removeAll { $0.plan.kind == .warmup && $0.completedAt == nil } }
            let position = activeSession!.exercises[e].sets.firstIndex { $0.plan.kind != .warmup && $0.completedAt == nil } ?? activeSession!.exercises[e].sets.count
            activeSession!.exercises[e].sets.insert(contentsOf: copies.map { LoggedSet(plan: $0, variant: variant) }, at: position)
            activeSession!.exercises[e].keepExpanded = nil
            if saveFuture { try applyWarmups(plans, toVariants: [variant.id], replacing: replacing) }
        }
        restDeadline = nil
    }
    mutating func removeWarmups(fromVariants ids: Set<UUID>) {
        for v in variants.indices where ids.contains(variants[v].id) { variants[v].sets.removeAll { $0.kind == .warmup } }
    }
    /// Logged warm-ups stay; only pending ones are removed.
    mutating func removePendingWarmups(fromSessionExercises ids: Set<UUID>) {
        guard activeSession != nil else { return }
        for e in activeSession!.exercises.indices where ids.contains(activeSession!.exercises[e].id) {
            activeSession!.exercises[e].sets.removeAll { $0.plan.kind == .warmup && $0.completedAt == nil }
        }
    }
}
