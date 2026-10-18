import SwiftUI
import LiftingCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import UserNotifications
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published var data: TrainingData
    @Published var error: String?
    @Published var storageBlocked = false
    @Published var workoutPresented = false
    @Published var autoFocusedExerciseID: UUID?
    @Published var autoFocusRevision = 0
    @Published var syncConfiguration = FolderSyncConfiguration()
    @Published var syncStatus = "Off"
    @Published var syncing = false
    @Published var lastFolderSync: Date?
    var syncState: DeviceSyncState?
    var syncGeneration = 0
    var syncConfigurationLoaded = false
    var pendingSync: Task<Void, Never>?
    let repository: LocalRepository?
    let demo: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        demo = arguments.contains("--demo")
        let directoryIndex = arguments.firstIndex(of: "--data-directory")
        let testDirectory = directoryIndex.flatMap { index in arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1], isDirectory: true) : nil }
        if demo && testDirectory == nil {
            repository = nil; data = .demo(); return
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
            _ = try next.validated()
            try repository?.save(next)
            data = next
            scheduleFolderSync()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func start(_ routine: Routine) { perform { try $0.start(routineID: routine.id) }; if data.activeSession != nil { workoutPresented = true } }
    func emptyWorkout() { perform { d in guard d.activeSession == nil else { return }; d.activeSession = Session(name: "Workout") }; workoutPresented = true }
    func finish() { perform { try $0.finish() }; if data.activeSession == nil { workoutPresented = false; cancelRestAlert() } }
    func discard() { perform { $0.activeSession = nil; $0.restDeadline = nil }; workoutPresented = false; cancelRestAlert() }

    func editActive(_ change: (inout Session) -> Void) { perform { d in if var session = d.activeSession { change(&session); d.activeSession = session } } }
    func editExercise(_ id: UUID, _ change: (inout SessionExercise) -> Void) {
        editActive { session in if let i = session.exercises.firstIndex(where: { $0.id == id }) { change(&session.exercises[i]) } }
    }
    func editSet(_ exerciseID: UUID, _ setID: UUID, _ change: (inout LoggedSet) -> Void) {
        editExercise(exerciseID) { e in if let i = e.sets.firstIndex(where: { $0.id == setID }) { change(&e.sets[i]) } }
    }
    func toggle(_ exerciseID: UUID, _ setID: UUID) {
        let before = data.activeSession?.completedSets ?? 0
        perform { try $0.toggleSet(exerciseID: exerciseID, setID: setID) }
        if (data.activeSession?.completedSets ?? 0) > before {
            haptic(); scheduleRestAlert()
            if data.activeSession?.linkTitle(for: exerciseID) != nil, let target = data.activeSession?.exercises.first(where: { $0.collapsed == false }) {
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
        perform { d in
            if let i = d.variants.firstIndex(where: { $0.id == variant.id }) { d.variants[i] = variant }
            else { d.variants.append(variant) }
        }
    }
    func add(_ exercise: Exercise, to routineID: UUID) {
        perform { d in
            guard let i = d.routines.firstIndex(where: { $0.id == routineID }) else { return }
            let base = [d.programForDay(routineID)?.name, d.routines[i].name].compactMap { $0 }.joined(separator: " · ")
            let label = TrainingData.uniqueName(base, among: d.variants.filter { $0.exerciseID == exercise.id }.map(\.label))
            let variant = Self.newVariant(exercise, label: label)
            d.variants.append(variant); d.routines[i].slots.append(RoutineSlot(variantID: variant.id))
        }
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
            data = next; storageBlocked = false; error = nil; workoutPresented = false; cancelRestAlert()
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
func planSummary(_ variant: Variant, unit: WeightUnit) -> String {
    let work = variant.sets.filter { $0.kind != .warmup }
    guard let first = work.first else { return "\(variant.sets.count) warm-up sets" }
    var parts = [counted(work.count, "set")]
    if let reps = first.reps { parts.append(first.repCeiling != nil && first.repCeiling != reps ? "\(reps)-\(first.repCeiling!) reps" : "\(reps) reps") }
    if first.load != .none { parts.append("\(number(unit.display(variant.workingWeight))) \(unit.rawValue)") }
    if let seconds = first.seconds { parts.append(clockText(seconds)) }
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
        if let reps = set.reps { parts.append("\(group.count) × \(reps) reps") }
        else if let range = set.plan.repRange { parts.append("\(group.count) × \(range.lowerBound)-\(range.upperBound) reps") }
        else { parts.append(counted(group.count, "set")) }
        if let weight = set.weight { parts.append("\(number(unit.display(weight))) \(unit.rawValue)") }
        if let seconds = set.seconds { parts.append(clockText(seconds)) }
        if let meters = set.meters { parts.append("\(number(meters)) m") }
        if let rpe = set.rpe { parts.append("@\(number(rpe))") }
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
