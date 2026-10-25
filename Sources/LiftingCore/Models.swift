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
    /// Drop and MYO setup for this exercise. Nil uses the app-wide defaults.
    public var techniques: TechniqueDefaults?
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
    /// An explicit working-set entry. Nil inherits the preceding working-set entry.
    public var weightOverride: Double?
    public init(id: UUID = UUID(), kind: SetKind = .working, load: LoadRule = .working, fixedWeight: Double = 0, percent: Double = 50, reps: Int? = 8, repCeiling: Int? = 12, seconds: Double? = nil, meters: Double? = nil, rpe: Double? = nil, amrap: Bool = false, restSeconds: Int? = nil) {
        self.id = id; self.kind = kind; self.load = load; self.fixedWeight = fixedWeight; self.percent = percent
        self.reps = reps; self.repCeiling = repCeiling; self.seconds = seconds; self.meters = meters; self.rpe = rpe; self.amrap = amrap; self.restSeconds = restSeconds
    }
    public var isValid: Bool {
        func number(_ value: Double, maximum: Double = 10_000_000) -> Bool { value.isFinite && (0...maximum).contains(value) }
        // Loads may be negative: assisted bodyweight sets record the assistance as a negative load.
        func load(_ value: Double) -> Bool { value.isFinite && abs(value) <= 10_000_000 }
        return load(fixedWeight) && (weightOverride.map(load) ?? true)
            && number(percent, maximum: 1000) && (reps.map { (0...10000).contains($0) } ?? true)
            && (repCeiling.map { $0 >= (reps ?? 0) && $0 <= 10000 } ?? true)
            && (seconds.map { number($0) } ?? true) && (meters.map { number($0) } ?? true)
            && (rpe.map { number($0, maximum: 10) } ?? true) && (restSeconds.map { (0...86400).contains($0) } ?? true)
    }
    public var repRange: ClosedRange<Int>? {
        guard let reps, let repCeiling, repCeiling > reps else { return nil }
        return reps...repCeiling
    }
    /// Reps filled in before logging. Ranges and AMRAP sets start empty so nothing is assumed.
    public var initialReps: Int? { repRange == nil && !amrap ? reps : nil }
    /// "8", "8-12", "5+" for AMRAP with a goal, or "AMRAP" without one.
    public var repTarget: String? {
        if amrap { return reps.map { "\($0)+" } ?? "AMRAP" }
        guard let reps else { return nil }
        return repRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? String(reps)
    }
    public func hasSameTarget(as other: SetPlan) -> Bool { reps == other.reps && repCeiling == other.repCeiling && amrap == other.amrap }
    public mutating func takeTarget(from other: SetPlan) { reps = other.reps; repCeiling = other.repCeiling; amrap = other.amrap }
    /// A failure set aims past its target: the target's minimum becomes an AMRAP goal, so 8-12 reads "8+".
    /// The range is kept, so leaving failure restores it.
    public mutating func markToFailure() {
        kind = .failure
        if reps != nil { amrap = true }
    }
    public func resolvedWeight(working: Double, increment: Double) -> Double? {
        switch load {
        case .none: return nil
        case .working: return weightOverride ?? working
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
    public var title: String { self == .manual ? "None" : self == .linear ? "Linear" : "Double progression" }
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
    /// Rest after warm-ups, and after a set logged below its target. Nil uses the app setting.
    public var warmupRestSeconds: Int?
    public var failRestSeconds: Int?
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
    /// A logged count below the set's target: its minimum, exact count, or AMRAP goal.
    public var missedTarget: Bool {
        guard let reps, let goal = plan.amrap ? plan.reps : plan.repRange?.lowerBound ?? plan.reps else { return false }
        return reps < goal
    }
    /// Explicit entries survive later changes to the exercise's suggested load.
    public var weightIsEdited: Bool?
    public init(plan: SetPlan, variant: Variant) {
        id = UUID(); self.plan = plan; weightIsEdited = plan.load == .working && plan.weightOverride != nil
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
    public var warmupRestSeconds: Int?
    public var failRestSeconds: Int?
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
        warmupRestSeconds = variant.warmupRestSeconds; failRestSeconds = variant.failRestSeconds
        workingWeight = variant.workingWeight; roundingIncrement = variant.rounding
        let weights = variant.resolvedWeights
        sets = variant.sets.enumerated().map { index, plan in
            var set = LoggedSet(plan: plan, variant: variant)
            // A load derived from an unset working weight is unknown, not zero.
            set.weight = weights[index].flatMap { $0 == 0 && plan.load != .fixed ? nil : $0 }
            return set
        }
    }
    public func workingLoad(fallback: Double) -> Double {
        sets.first(where: { $0.plan.kind != .warmup && $0.plan.load != .none })?.weight ?? workingWeight ?? fallback
    }
    /// Rest after a logged set: its own rest, else warm-up rest, else the longer rest after a missed target
    /// when one is set, else the exercise's rest.
    public func rest(after set: LoggedSet, settings: Settings) -> Int {
        if let own = set.plan.restSeconds { return own }
        if set.plan.kind == .warmup { return warmupRestSeconds ?? settings.warmupRestDefault }
        return max(restSeconds, failRest(after: set, settings: settings) ?? 0)
    }
    /// The longer rest after a set logged below its target. A MYO mini-set that falls short ends its cluster
    /// as planned, and drops chain without rest, so neither counts as a miss here.
    public func failRest(after set: LoggedSet, settings: Settings) -> Int? {
        guard set.missedTarget, ![.myoMini, .drop].contains(set.plan.kind) else { return nil }
        return failRestSeconds ?? settings.failRest
    }
    /// The load a set moved: for bodyweight exercises, body weight plus any added (or minus assisted) weight.
    /// Nil when the load is unknown, so it adds no invented volume.
    public func load(of set: LoggedSet, bodyWeight: Double?) -> Double? {
        guard mode == .bodyweight else { return set.weight }
        return bodyWeight.map { max(0, $0 + (set.weight ?? 0)) }
    }
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
    /// Body weight logged on or before the workout, used for bodyweight exercise volume.
    public var bodyWeight: Double?
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var pausedAt: Date?
    public var pauses: [DateInterval]?
    public var lastActivityAt: Date?
    public var notes: String
    public var exercises: [SessionExercise]
    public init(id: UUID = UUID(), routineID: UUID? = nil, name: String, startedAt: Date = Date(), endedAt: Date? = nil, exercises: [SessionExercise] = []) {
        self.id = id; self.routineID = routineID; self.name = name; self.startedAt = startedAt; self.endedAt = endedAt; self.exercises = exercises; notes = ""
    }
    public var completedSets: Int { exercises.flatMap(\.sets).filter { $0.completedAt != nil }.count }
    public var totalSets: Int { exercises.flatMap(\.sets).count }
    public func duration(at now: Date = Date()) -> TimeInterval {
        let pausedSeconds = (pauses ?? []).reduce(0) { $0 + $1.duration }
        return max(0, (endedAt ?? pausedAt ?? now).timeIntervalSince(startedAt) - pausedSeconds)
    }
    public var volume: Double { volume(warmups: false) }
    public var warmupVolume: Double { volume(warmups: true) }
    private func volume(warmups: Bool) -> Double {
        exercises.reduce(0) { total, exercise in
            exercise.sets.filter { $0.completedAt != nil && ($0.plan.kind == .warmup) == warmups }
                .reduce(total) { $0 + (exercise.load(of: $1, bodyWeight: bodyWeight) ?? 0) * Double($1.reps ?? 0) }
        }
    }
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
    public var workoutReminders: Bool?
    public var collapsesCompletedExercises: Bool { autoCollapseCompleted ?? true }
    public var remindsAboutUnfinishedWorkouts: Bool { workoutReminders ?? true }
    public var colors: ColorTheme?
    /// The two quick-add buttons under each live exercise: "drop", "myo", "warmup", "failure", or "type:<uuid>".
    public var quickAdd: [String]?
    /// Seconds the rest timer's − and + buttons change.
    public var restStep: Int?
    public var restAdjustment: Int { restStep ?? 15 }
    /// App-wide Drop and MYO setup; an exercise can override it.
    public var techniques: TechniqueDefaults?
    /// Rest after warm-up sets. Exercises can override it.
    public var warmupRest: Int?
    public var warmupRestDefault: Int { get { warmupRest ?? 60 } set { warmupRest = newValue } }
    /// Rest after a set logged below its target. Nil is off; exercises can override it.
    public var failRest: Int?
    /// Moves an exercise up to follow the ones already worked on when its first set is logged.
    public var autoOrder: Bool?
    public var ordersExercisesAsLogged: Bool { get { autoOrder ?? true } set { autoOrder = newValue } }
    /// Shows warm-up volume next to total volume. Warm-ups never count toward volume.
    public var showsWarmupVolume: Bool?
    /// The warm-up preset applied most recently, offered again in each exercise's menu.
    public var lastWarmups: WarmupPreset?
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
    public var bodyWeights: [BodyWeightEntry] = []
    public var activeProgramID: UUID?
    public var sessions: [Session] = []
    public var historyImports: [HistoryImportLink] = []
    public var activeSession: Session?
    public var restDeadline: Date?
    public var settings: Settings = Settings()
    public init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, exercises, variants, routines, programs, warmupPresets, customSetTypes, bodyWeights, activeProgramID, sessions, historyImports, activeSession, restDeadline, settings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exercises = try c.decode([Exercise].self, forKey: .exercises)
        variants = try c.decode([Variant].self, forKey: .variants)
        routines = try c.decode([Routine].self, forKey: .routines)
        programs = try c.decodeIfPresent([TrainingProgram].self, forKey: .programs) ?? []
        warmupPresets = try c.decodeIfPresent([WarmupPreset].self, forKey: .warmupPresets) ?? []
        customSetTypes = try c.decodeIfPresent([CustomSetType].self, forKey: .customSetTypes) ?? []
        bodyWeights = try c.decodeIfPresent([BodyWeightEntry].self, forKey: .bodyWeights) ?? []
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
