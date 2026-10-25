import SwiftUI
import LiftingCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import UserNotifications
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published var data: TrainingData {
        didSet { if oldValue.sessions != data.sessions { previousByVariant = nil } }
    }
    private var previousByVariant: [UUID: [LoggedSet]]?
    @Published var error: String?
    @Published var storageBlocked = false
    @Published var workoutPresented = false
    @Published var autoFocusedExerciseID: UUID?
    @Published var autoFocusRevision = 0
    /// When the current rest began, so the rest ring keeps its scale across ±15 and reopening the workout.
    @Published var restStartedAt: Date?
    /// Bumped when a workout ends, so Train returns to its first screen.
    @Published var trainRevision = 0
    @Published var syncConfiguration = FolderSyncConfiguration()
    @Published var syncStatus = "Off"
    @Published var syncing = false
    @Published var lastFolderSync: Date?
    /// Last Apple Health problem, shown in Settings.
    @Published var healthStatus: String?
    #if canImport(HealthKit) && os(iOS)
    let health: HealthBridge? = HealthBridge.isAvailable ? HealthBridge() : nil
    #endif
    var healthRefreshing = false
    var healthRefreshPending = false
    /// How long Lifting waits for a watch workout before saving its own. `--health-save-delay` shortens it for testing.
    let healthSaveDelay: TimeInterval = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--health-save-delay"), arguments.indices.contains(index + 1), let value = TimeInterval(arguments[index + 1]) else { return HealthMatching.saveDelay }
        return max(0, value)
    }()
    var syncState: DeviceSyncState?
    var syncGeneration = 0
    var syncConfigurationLoaded = false
    var pendingSync: Task<Void, Never>?
    let repository: LocalRepository?
    let notifications = WorkoutNotifications()
    let demo: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let showcase = arguments.contains("--showcase")
        demo = arguments.contains("--demo") || showcase
        let directoryIndex = arguments.firstIndex(of: "--data-directory")
        let testDirectory = directoryIndex.flatMap { index in arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1], isDirectory: true) : nil }
        if demo && testDirectory == nil {
            repository = nil; data = showcase ? .showcase() : .demo(); return
        }
        let root = testDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Lifting", isDirectory: true)
        repository = LocalRepository(url: root.appendingPathComponent("training.json"))
        do {
            let loaded = try repository!.load()
            data = loaded?.data ?? (demo ? .demo() : .starter())
            if loaded?.recoveredBackup == true { error = "Recovered the previous local save. Export a backup now." }
        } catch {
            data = TrainingData(); storageBlocked = true; self.error = error.localizedDescription
        }
    }

    @discardableResult func perform(_ change: (inout TrainingData) throws -> Void) -> Bool {
        guard !storageBlocked else { error = "Import a valid backup in Settings to recover your preserved data."; return false }
        var next = data
        do {
            try change(&next)
            guard next != data else { return true }
            let workoutChanged = next.activeSession != data.activeSession
            if workoutChanged, next.activeSession != nil { next.activeSession?.lastActivityAt = Date() }
            _ = try next.validated()
            try repository?.save(next)
            let remindersChanged = next.settings.workoutReminders != data.settings.workoutReminders
            data = next
            if workoutChanged || remindersChanged { refreshWorkoutReminders() }
            scheduleFolderSync()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func previousSets(for variantID: UUID) -> [LoggedSet] {
        if previousByVariant == nil {
            var result: [UUID: [LoggedSet]] = [:]
            for session in data.sessions.filter({ $0.skipped != true }).sorted(by: { $0.startedAt > $1.startedAt }) {
                for item in session.exercises where result[item.variantID] == nil { result[item.variantID] = item.sets }
            }
            previousByVariant = result
        }
        return previousByVariant?[variantID] ?? []
    }

    func start(_ routine: Routine) { perform { try $0.start(routineID: routine.id) }; if data.activeSession != nil { workoutPresented = true } }
    func emptyWorkout() { perform { d in guard d.activeSession == nil else { return }; d.activeSession = Session(name: "Workout") }; workoutPresented = true }
    func finish() { perform { try $0.finish() }; if data.activeSession == nil { workoutPresented = false; cancelRestAlert(); trainRevision += 1; scheduleHealthCheck() } }
    /// Deletes a workout from history, and the copy Lifting saved to Apple Health for it.
    func deleteSession(_ id: UUID) {
        let copies = data.sessions.first { $0.id == id }?.health?.savedWorkoutIDs ?? []
        if perform({ $0.sessions.removeAll { $0.id == id } }) { deleteHealthCopies(copies) }
    }
    func discard() { perform { $0.activeSession = nil; $0.restDeadline = nil }; workoutPresented = false; cancelRestAlert(); trainRevision += 1 }
    func setHiddenFromProgress(_ exerciseID: UUID, _ hidden: Bool) {
        perform { d in if let i = d.exercises.firstIndex(where: { $0.id == exerciseID }) { d.exercises[i].hiddenFromProgress = hidden ? true : nil } }
    }
        func skipNext(in programID: UUID) { perform { try $0.skipNextDay(in: programID) } }

    func editActive(_ change: (inout Session) -> Void) { perform { d in if var session = d.activeSession { change(&session); d.activeSession = session } } }
    func editExercise(_ id: UUID, _ change: (inout SessionExercise) -> Void) {
        editActive { session in if let i = session.exercises.firstIndex(where: { $0.id == id }) { change(&session.exercises[i]) } }
    }
    func editSet(_ exerciseID: UUID, _ setID: UUID, _ change: (inout LoggedSet) -> Void) {
        editExercise(exerciseID) { e in if let i = e.sets.firstIndex(where: { $0.id == setID }) { change(&e.sets[i]) } }
    }
    /// Completes a pending set once it has a rep count, as confirming reps on the keypad does.
    func completeIfLogged(_ exerciseID: UUID, _ setID: UUID) {
        guard let set = data.activeSession?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == setID }),
              set.completedAt == nil, set.reps != nil else { return }
        toggle(exerciseID, setID)
    }
    func toggle(_ exerciseID: UUID, _ setID: UUID) {
        let before = data.activeSession?.completedSets ?? 0
        let previousDeadline = data.restDeadline
        perform { try $0.toggleSet(exerciseID: exerciseID, setID: setID) }
        if data.restDeadline != previousDeadline { restStartedAt = data.restDeadline == nil ? nil : Date() }
        if (data.activeSession?.completedSets ?? 0) > before {
            haptic(); scheduleRestAlert()
            // Scroll only when focus moves to another exercise, so rows stay put while logging the same one.
            if data.activeSession?.linkTitle(for: exerciseID) != nil, let target = data.activeSession?.exercises.first(where: { $0.collapsed == false }), target.id != exerciseID {
                autoFocusedExerciseID = target.id; autoFocusRevision += 1
            }
        }
        else { cancelRestAlert() }
    }
    func adjustRest(_ seconds: Double) {
        perform { d in if let deadline = d.restDeadline { d.restDeadline = max(Date(), deadline).addingTimeInterval(seconds) } }
        scheduleRestAlert()
    }
    func skipRest() { perform { $0.restDeadline = nil }; cancelRestAlert() }
    @discardableResult func saveVariant(_ variant: Variant) -> Bool {
        var variant = variant
        if let first = variant.sets.first(where: { $0.kind != .warmup && $0.load == .working }), let weight = first.weightOverride { variant.workingWeight = weight }
        return perform { d in
            if let i = d.variants.firstIndex(where: { $0.id == variant.id }) { d.variants[i] = variant }
            else { d.variants.append(variant) }
        }
    }
    @discardableResult func add(_ exercises: [Exercise], to routineID: UUID) -> Bool {
        perform { try $0.addExercises(exercises.map(\.id), to: routineID) }
    }
    func prepareNotifications() {
        notifications.configure()
        notifications.openWorkout = { [weak self] id in
            guard let self, self.data.activeSession?.id == id else { return }
            self.workoutPresented = true
        }
        refreshWorkoutReminders()
    }
    func refreshWorkoutReminders() {
        guard !demo else { return }
        notifications.refresh(session: data.activeSession, enabled: data.settings.remindsAboutUnfinishedWorkouts)
    }
    func requestWorkoutAlerts() {
        guard !demo, data.settings.remindsAboutUnfinishedWorkouts else { return }
        Task { if await notifications.requestPermission() { refreshWorkoutReminders() } }
    }
    func pauseWorkout(_ paused: Bool) {
        perform { $0.setWorkoutPaused(paused) }
        if paused { cancelRestAlert() }
    }
    func addToWorkout(_ exercise: Exercise) {
        perform { try $0.addExerciseToSession(exercise.id) }
    }
    static func newVariant(_ exercise: Exercise, label: String) -> Variant {
        Variant.standard(for: exercise, label: label)
    }
    func importBackup(_ next: TrainingData) {
        do {
            _ = try next.validated()
            // Preserve the complete pre-import state separately from rolling autosave recovery.
            if !storageBlocked, let repository {
                try FileManager.default.createDirectory(at: repository.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try LocalRepository.encode(data).write(to: repository.url.appendingPathExtension("before-import"), options: .atomic)
            } else if storageBlocked, let repository, let raw = try? Data(contentsOf: repository.url) {
                try raw.write(to: repository.url.appendingPathExtension("before-import"), options: .atomic)
            }
            try repository?.save(next)
            data = next; storageBlocked = false; error = nil; workoutPresented = false; cancelRestAlert(); refreshWorkoutReminders()
            scheduleFolderSync()
        } catch { self.error = "Import failed. \(error.localizedDescription)" }
    }
    func haptic() {
        #if os(iOS)
        if data.settings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        #endif
    }
    func collapseCompleted(_ id: UUID) {
        var nextID: UUID?
        if perform({ nextID = $0.collapseCompletedExercise(id) }), let nextID { autoFocusedExerciseID = nextID; autoFocusRevision += 1 }
    }
    func scheduleRestAlert() {
        #if os(iOS)
        cancelRestAlert()
        guard let deadline = data.restDeadline, deadline.timeIntervalSinceNow > 0 else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent(); content.title = "Rest complete"; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
        }
        #endif
    }
    func cancelRestAlert() {
        #if os(iOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        #endif
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var bytes: Data
    init(bytes: Data = Data()) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

func number(_ value: Double, decimals: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(0...decimals)).grouping(.never))
}
func counted(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }
func clockText(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.rounded(.up)))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}
/// The sets counted in "sets × reps": working and failure sets, so drop and MYO follow-ups are not
/// read as extra work sets. Falls back to every non-warm-up set, for example a MYO-only prescription.
func prescribedWork(_ plans: [SetPlan]) -> [SetPlan] {
    let main = plans.filter { $0.kind == .working || $0.kind == .failure }
    return main.isEmpty ? plans.filter { $0.kind != .warmup } : main
}

/// One-line prescription in the app's standard form, for example "3 × 5 · 95 lb · RPE 8".
func planSummary(_ variant: Variant, unit: WeightUnit) -> String {
    let work = prescribedWork(variant.sets)
    guard let first = work.first else { return counted(variant.sets.count, "warm-up") }
    var parts: [String] = []
    if let target = first.repTarget { parts.append("\(work.count) × \(displayTarget(target))") }
    else if let seconds = first.seconds { parts.append(work.count > 1 ? "\(work.count) × \(clockText(seconds))" : clockText(seconds)) }
    else { parts.append(counted(work.count, "set")) }
    let weights = zip(variant.sets, variant.resolvedWeights).compactMap { $0.kind == .warmup ? nil : $1 }
    if !weights.isEmpty { parts.append(weightSummary(weights, unit: unit)) }
    if first.repTarget != nil, let seconds = first.seconds { parts.append(clockText(seconds)) }
    if let rpe = first.rpe { parts.append("RPE \(number(rpe))") }
    return parts.joined(separator: " · ")
}

func loggedExerciseSummary(_ exercise: SessionExercise, unit: WeightUnit) -> String {
    let completed = exercise.sets.filter { $0.completedAt != nil }
    let working = completed.filter { $0.plan.kind != .warmup }
    let sets = working.isEmpty ? completed : working
    guard !sets.isEmpty else { return "0 sets" }
    var groups: [[LoggedSet]] = []
    for set in sets {
        if let last = groups.last?.last,
           last.weight == set.weight, last.reps == set.reps, last.seconds == set.seconds,
           last.meters == set.meters, last.rpe == set.rpe, last.plan.kind == set.plan.kind,
           (set.reps != nil || last.plan.repTarget == set.plan.repTarget) {
            groups[groups.count - 1].append(set)
        } else { groups.append([set]) }
    }
    return groups.map { group in
        guard let set = group.first else { return "" }
        var parts: [String] = []
        if let reps = set.reps { parts.append("\(group.count) × \(reps)") }
        else if let range = set.plan.repRange { parts.append("\(group.count) × \(range.lowerBound)–\(range.upperBound)") }
        else if group.count > 1 || (set.seconds == nil && set.meters == nil && set.weight == nil) { parts.append(counted(group.count, "set")) }
        if let weight = set.weight { parts.append("\(number(unit.display(weight))) \(unit.rawValue)") }
        if let seconds = set.seconds { parts.append(clockText(seconds)) }
        if let meters = set.meters { parts.append("\(number(meters)) m") }
        if let rpe = set.rpe { parts.append("RPE \(number(rpe))") }
        switch set.plan.kind {
        case .working: break
        case .warmup: parts.append("Warm-up")
        case .drop: parts.append("Drop")
        case .myoActivation: parts.append("Activation")
        case .myoMini: parts.append("Mini-set")
        case .failure: parts.append("Failure")
        }
        return parts.joined(separator: " · ")
    }.joined(separator: "\n")
}

/// "8–12" for display; stored targets use a plain hyphen.
func displayTarget(_ target: String) -> String { target.replacingOccurrences(of: "-", with: "–") }

/// A set's load as entered. Bodyweight sets show what was added or assisted: "BW", "+25", "−40".
func loadText(_ kilograms: Double?, mode: ExerciseMode, unit: WeightUnit) -> String? {
    guard mode == .bodyweight else { return kilograms.map { number(unit.display($0)) } }
    guard let kilograms, abs(kilograms) > 0.00001 else { return "BW" }
    return (kilograms > 0 ? "+" : "−") + number(unit.display(abs(kilograms)))
}

/// The working load line under an exercise: a weight or range, or the added load for bodyweight work.
func loadSummary(_ weights: [Double?], mode: ExerciseMode, unit: WeightUnit) -> String? {
    let values = weights.compactMap { $0 }
    switch mode {
    case .cardio: return nil
    case .strength: return values.isEmpty ? nil : weightSummary(values, unit: unit)
    case .bodyweight:
        guard let low = values.min(), let high = values.max(), abs(low) > 0.00001 || abs(high) > 0.00001 else { return nil }
        let lower = loadText(low, mode: mode, unit: unit) ?? ""
        return "\(lower)\(abs(high - low) < 0.00001 ? "" : " to " + (loadText(high, mode: mode, unit: unit) ?? "")) \(unit.rawValue)"
    }
}

/// A range avoids implying that independent sets share an editable base weight.
func weightSummary(_ weights: [Double], unit: WeightUnit) -> String {
    guard let low = weights.min(), let high = weights.max() else { return "–" }
    let lower = number(unit.display(low))
    return "\(lower)\(abs(high - low) < 0.00001 ? "" : "–" + number(unit.display(high))) \(unit.rawValue)"
}
