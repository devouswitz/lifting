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

    func perform(_ change: (inout TrainingData) throws -> Void) {
        guard !storageBlocked else { error = "Import a valid backup in Settings to recover your preserved data."; return }
        var next = data
        do {
            try change(&next)
            _ = try next.validated()
            try repository?.save(next)
            data = next
        } catch { self.error = error.localizedDescription }
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
        if (data.activeSession?.completedSets ?? 0) > before { haptic(); scheduleRestAlert() }
        else { cancelRestAlert() }
    }
    func adjustRest(_ seconds: Double) {
        perform { d in if let deadline = d.restDeadline { d.restDeadline = max(Date(), deadline).addingTimeInterval(seconds) } }
        scheduleRestAlert()
    }
    func skipRest() { perform { $0.restDeadline = nil }; cancelRestAlert() }
    func saveVariant(_ variant: Variant) {
        perform { d in
            if let i = d.variants.firstIndex(where: { $0.id == variant.id }) { d.variants[i] = variant }
            else { d.variants.append(variant) }
        }
    }
    func add(_ exercise: Exercise, to routineID: UUID) {
        perform { d in
            guard let i = d.routines.firstIndex(where: { $0.id == routineID }) else { return }
            var label = d.routines[i].name
            var n = 2
            while d.variants.contains(where: { $0.exerciseID == exercise.id && $0.label == label }) { label = "\(d.routines[i].name) \(n)"; n += 1 }
            let variant = Self.newVariant(exercise, label: label)
            d.variants.append(variant); d.routines[i].slots.append(RoutineSlot(variantID: variant.id))
        }
    }
    func addToWorkout(_ exercise: Exercise) {
        perform { d in
            guard d.activeSession != nil else { return }
            let label = d.activeSession!.name
            let variant = d.variants.first { $0.exerciseID == exercise.id && $0.label == label } ?? Self.newVariant(exercise, label: label)
            if !d.variants.contains(where: { $0.id == variant.id }) { d.variants.append(variant) }
            d.activeSession!.exercises.append(SessionExercise(variant: variant, exercise: exercise))
        }
    }
    static func newVariant(_ exercise: Exercise, label: String) -> Variant {
        var variant = Variant(exerciseID: exercise.id, label: label)
        if exercise.mode == .cardio { variant.sets = [SetPlan(load: .none, reps: nil, repCeiling: nil, seconds: 1200, rpe: 6)]; variant.restSeconds = 0 }
        if exercise.mode == .bodyweight { variant.sets = (0..<3).map { _ in SetPlan(load: .none) } }
        return variant
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
        } catch { self.error = "Import failed. \(error.localizedDescription)" }
    }
    func haptic() {
        #if os(iOS)
        if data.settings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        #endif
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
