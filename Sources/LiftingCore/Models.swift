import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case lb, kg
    public var id: String { rawValue }
    public func kilograms(_ value: Double) -> Double { self == .kg ? value : value * 0.45359237 }
    public func display(_ kilograms: Double) -> Double { self == .kg ? kilograms : kilograms / 0.45359237 }
}

public enum ExerciseMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength, bodyweight, cardio
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String { self == .cardio ? "figure.run" : self == .bodyweight ? "figure.strengthtraining.functional" : "dumbbell" }
}

public struct Exercise: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var muscle: String
    public var equipment: String
    public var mode: ExerciseMode
    public var secondaryMuscles: [String]?
    /// Leaves the exercise out of the Progress overview; its own progress screen still works.
    public var hiddenFromProgress: Bool?
    public init(id: UUID = UUID(), name: String, muscle: String = "Other", equipment: String = "", mode: ExerciseMode = .strength) {
        self.id = id; self.name = name; self.muscle = muscle; self.equipment = equipment; self.mode = mode
    }
}

public enum SetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case warmup, working, drop, myoActivation, myoMini, failure
    public var id: String { rawValue }
    public var title: String { switch self { case .warmup: return "Warm-up"; case .working: return "Working"; case .drop: return "Drop set"; case .myoActivation: return "MYO activation"; case .myoMini: return "MYO mini-set"; case .failure: return "Failure" } }
}

public enum LoadRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case working, percent, fixed, none
    public var id: String { rawValue }
    public var title: String {
        switch self { case .working: return "Working weight"; case .percent: return "% of working set"; case .fixed: return "Fixed weight"; case .none: return "No weight" }
    }
}

public struct SetPlan: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: SetKind
    public var load: LoadRule
    public var fixedWeight: Double
    public var percent: Double
    public var reps: Int?
    public var repCeiling: Int?
    public var seconds: Double?
    public var meters: Double?
    public var rpe: Double?
    public var amrap: Bool
    public var restSeconds: Int?
    /// A user-named set type. `kind` still decides how the set counts.
    public var customTypeID: UUID?
    public init(id: UUID = UUID(), kind: SetKind = .working, load: LoadRule = .working, fixedWeight: Double = 0, percent: Double = 50, reps: Int? = 8, repCeiling: Int? = 12, seconds: Double? = nil, meters: Double? = nil, rpe: Double? = nil, amrap: Bool = false, restSeconds: Int? = nil) {
        self.id = id; self.kind = kind; self.load = load; self.fixedWeight = fixedWeight; self.percent = percent
        self.reps = reps; self.repCeiling = repCeiling; self.seconds = seconds; self.meters = meters; self.rpe = rpe; self.amrap = amrap; self.restSeconds = restSeconds
    }
    public var repRange: ClosedRange<Int>? {
        guard let reps, let repCeiling, repCeiling > reps else { return nil }
        return reps...repCeiling
    }
    public var initialReps: Int? { repRange == nil ? reps : nil }
    public var repTarget: String? {
        guard let reps else { return nil }
        return repRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? String(reps)
    }
    public func resolvedWeight(working: Double, increment: Double) -> Double? {
        switch load {
        case .none: return nil
        case .working: return working
        case .fixed: return fixedWeight
        case .percent:
            let result = working * percent / 100
            return increment > 0 ? floor((result + 0.000001) / increment) * increment : result
        }
    }
}

public enum ProgressionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, linear, double
    public var id: String { rawValue }
    public var title: String { self == .manual ? "Manual" : self == .linear ? "Linear" : "Double progression" }
}

public struct Progression: Codable, Equatable, Sendable {
    public var mode: ProgressionMode = .manual
    public var increment: Double = WeightUnit.lb.kilograms(5)
    public var deloadAfter: Int = 3
    public var deloadPercent: Double = 10
    public var failures: Int = 0
    public init() {}
}

public struct Variant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var exerciseID: UUID
    public var label: String
    public var workingWeight: Double
    public var rounding: Double
    public var restSeconds: Int
    public var notes: String
    public var sets: [SetPlan]
    public var progression: Progression
    public var substitutionSourceID: UUID?
    public init(id: UUID = UUID(), exerciseID: UUID, label: String, workingWeight: Double = 0, rounding: Double = WeightUnit.lb.kilograms(2.5), restSeconds: Int = 90, notes: String = "", sets: [SetPlan] = [SetPlan(), SetPlan(), SetPlan()], progression: Progression = Progression()) {
        self.id = id; self.exerciseID = exerciseID; self.label = label; self.workingWeight = workingWeight; self.rounding = rounding
        self.restSeconds = restSeconds; self.notes = notes; self.sets = sets; self.progression = progression
    }
}

public struct RoutineSlot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var variantID: UUID
    public var group: String
    public var groupRestSeconds: Int?
    public var transitionSeconds: Int?
    public init(id: UUID = UUID(), variantID: UUID, group: String = "") { self.id = id; self.variantID = variantID; self.group = group }
}

public struct Routine: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var slots: [RoutineSlot]
    public init(id: UUID = UUID(), name: String, notes: String = "", slots: [RoutineSlot] = []) {
        self.id = id; self.name = name; self.notes = notes; self.slots = slots
    }
}

public struct LoggedSet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var plan: SetPlan
    public var weight: Double?
    public var reps: Int?
    public var seconds: Double?
    public var meters: Double?
    public var rpe: Double?
    public var completedAt: Date?
    public var sourceFields: [String: String]?
    public init(plan: SetPlan, variant: Variant) {
        id = UUID(); self.plan = plan
        weight = plan.resolvedWeight(working: variant.workingWeight, increment: variant.rounding)
        reps = plan.initialReps; seconds = plan.seconds; meters = plan.meters; rpe = plan.rpe
    }
}

public struct SessionExercise: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var slotID: UUID?
    public var variantID: UUID
    public var exerciseID: UUID
    public var name: String
    public var label: String
    public var mode: ExerciseMode
    public var muscle: String?
    public var secondaryMuscles: [String]?
    public var group: String?
    public var groupRestSeconds: Int?
    public var transitionSeconds: Int?
    public var recurringNotes: String
    public var notes: String
    public var restSeconds: Int
    public var substitutedFrom: String?
    public var progressionEligible: Bool
    public var timerStartedAt: Date?
    public var timerElapsed: Double
    public var workingWeight: Double?
    public var roundingIncrement: Double?
    public var collapsed: Bool?
    public var keepExpanded: Bool?
    public var sets: [LoggedSet]
    public init(variant: Variant, exercise: Exercise, slotID: UUID? = nil) {
        id = UUID(); self.slotID = slotID; variantID = variant.id; exerciseID = exercise.id
        name = exercise.name; label = variant.label; mode = exercise.mode; recurringNotes = variant.notes
        muscle = exercise.muscle; secondaryMuscles = exercise.secondaryMuscles
        notes = ""; restSeconds = variant.restSeconds; progressionEligible = true; timerElapsed = 0
        workingWeight = variant.workingWeight; roundingIncrement = variant.rounding
        sets = variant.sets.map { LoggedSet(plan: $0, variant: variant) }
    }
    public func workingLoad(fallback: Double) -> Double { workingWeight ?? sets.first(where: { $0.plan.load == .working && $0.completedAt == nil })?.weight ?? sets.first(where: { $0.plan.load == .working })?.weight ?? fallback }
}

public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var routineID: UUID?
    public var programID: UUID?
    public var programName: String?
    public var advancesProgram: Bool?
    /// A program day that was skipped: saved with every set unchecked, so history shows the gap.
    public var skipped: Bool?
    /// Calories and heart rate from the Apple Health workout recorded at the same time.
    public var health: HealthLink?
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var notes: String
    public var exercises: [SessionExercise]
    public init(id: UUID = UUID(), routineID: UUID? = nil, name: String, startedAt: Date = Date(), endedAt: Date? = nil, exercises: [SessionExercise] = []) {
        self.id = id; self.routineID = routineID; self.name = name; self.startedAt = startedAt; self.endedAt = endedAt; self.exercises = exercises; notes = ""
    }
    public var completedSets: Int { exercises.flatMap(\.sets).filter { $0.completedAt != nil }.count }
    public var totalSets: Int { exercises.flatMap(\.sets).count }
    public var volume: Double { exercises.flatMap(\.sets).filter { $0.completedAt != nil && $0.plan.kind != .warmup }.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) } }
}

public struct Settings: Codable, Equatable, Sendable {
    public var unit: WeightUnit = .lb
    public var theme: String = "system"
    public var autoRest: Bool = true
    public var haptics: Bool = true
    public var keepAwake: Bool = true
    public var barWeight: Double = WeightUnit.lb.kilograms(45)
    public var platesLB: [Double] = [45, 35, 25, 10, 5, 2.5]
    public var platesKG: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    public var lastBackupAt: Date?
    public var autoCollapseCompleted: Bool?
    public var colors: ColorTheme?
    /// The two quick-add buttons under each live exercise: "drop", "myo", "warmup", "failure", or "type:<uuid>".
    public var quickAdd: [String]?
    public var health: HealthSettings?
    public init() {}
}

public struct HistoryImportLink: Codable, Equatable, Sendable {
    public var sourceVariantID: UUID
    public var variantID: UUID
    public var sourceExerciseID: UUID
    public var exerciseID: UUID
    public init(sourceVariantID: UUID, variantID: UUID, sourceExerciseID: UUID, exerciseID: UUID) {
        self.sourceVariantID = sourceVariantID; self.variantID = variantID
        self.sourceExerciseID = sourceExerciseID; self.exerciseID = exerciseID
    }
}

public struct TrainingData: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var exercises: [Exercise] = []
    public var variants: [Variant] = []
    public var routines: [Routine] = []
    public var programs: [TrainingProgram] = []
    public var warmupPresets: [WarmupPreset] = []
    public var customSetTypes: [CustomSetType] = []
    public var activeProgramID: UUID?
    public var sessions: [Session] = []
    public var historyImports: [HistoryImportLink] = []
    public var activeSession: Session?
    public var restDeadline: Date?
    public var settings: Settings = Settings()
    public init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, exercises, variants, routines, programs, warmupPresets, customSetTypes, activeProgramID, sessions, historyImports, activeSession, restDeadline, settings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exercises = try c.decode([Exercise].self, forKey: .exercises)
        variants = try c.decode([Variant].self, forKey: .variants)
        routines = try c.decode([Routine].self, forKey: .routines)
        programs = try c.decodeIfPresent([TrainingProgram].self, forKey: .programs) ?? []
        warmupPresets = try c.decodeIfPresent([WarmupPreset].self, forKey: .warmupPresets) ?? []
        customSetTypes = try c.decodeIfPresent([CustomSetType].self, forKey: .customSetTypes) ?? []
        activeProgramID = try c.decodeIfPresent(UUID.self, forKey: .activeProgramID)
        sessions = try c.decode([Session].self, forKey: .sessions)
        historyImports = try c.decodeIfPresent([HistoryImportLink].self, forKey: .historyImports) ?? []
        activeSession = try c.decodeIfPresent(Session.self, forKey: .activeSession)
        restDeadline = try c.decodeIfPresent(Date.self, forKey: .restDeadline)
        settings = try c.decode(Settings.self, forKey: .settings)
    }
    public func exercise(_ id: UUID) -> Exercise? { exercises.first { $0.id == id } }
    public func variant(_ id: UUID) -> Variant? { variants.first { $0.id == id } }
}

public enum TrainingError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum Metric: String, CaseIterable, Identifiable, Sendable {
    case weight, volume, estimatedMax, reps, duration, distance, rpe
    public var id: String { rawValue }
    public var title: String {
        switch self { case .weight: return "Top weight"; case .volume: return "Volume"; case .estimatedMax: return "Estimated 1RM"; case .reps: return "Reps"; case .duration: return "Minutes"; case .distance: return "Distance (km)"; case .rpe: return "RPE" }
    }
}

public struct ProgressPoint: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var value: Double
}
