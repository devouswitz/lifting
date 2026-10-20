import Foundation
import LiftingCore
#if canImport(HealthKit) && os(iOS)
import HealthKit

/// Reads workouts from Apple Health and, when saving is on, writes Lifting's own.
/// Workouts from an Apple Watch or another app are only read; Lifting deletes only workouts it saved.
@MainActor
final class HealthBridge {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private let store = HKHealthStore()
    private let energy = HKQuantityType(.activeEnergyBurned)
    private let heartRate = HKQuantityType(.heartRate)
    private var observer: HKObserverQuery?

    func requestAccess(write: Bool) async throws {
        try await store.requestAuthorization(toShare: write ? [HKObjectType.workoutType()] : [], read: [HKObjectType.workoutType(), energy, heartRate])
    }
    /// Apple Health reports whether Lifting may save workouts; read access is never revealed.
    var canSave: Bool { store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized }

    /// Calls `changed` whenever workouts change in Apple Health while Lifting is running.
    func observe(_ changed: @escaping @Sendable () -> Void) {
        guard observer == nil else { return }
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { _, completion, error in
            if error == nil { changed() }
            completion()
        }
        observer = query
        store.execute(query)
    }
    func stopObserving() {
        if let observer { store.stop(observer) }
        observer = nil
    }

    /// Workouts that overlap `range`. Heart rate is looked up separately only for workouts near a session.
    func workouts(in range: DateInterval, near windows: [DateInterval]) async throws -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)], limit: 2000)
        let own = HKSource.default().bundleIdentifier
        var result: [HealthWorkout] = []
        for workout in try await descriptor.result(for: store) {
            let isOwn = workout.sourceRevision.source.bundleIdentifier == own
            let sessionID = (workout.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap(UUID.init(uuidString:))
            let kcal = workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? LegacyWorkoutEnergy.kilocalories(workout)
            var rate = workout.statistics(for: heartRate)?.averageQuantity()?.doubleValue(for: Self.bpm)
            let span = DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate))
            let near = windows.filter { $0.intersects(span) }.count
            if rate == nil, !isOwn, near > 0 { rate = try? await averageHeartRate(from: workout.startDate, to: workout.endDate) }
            // A workout kept running across two sessions is split by when its energy was burned.
            let segments = !isOwn && near > 1 ? try? await energySegments(of: workout) : nil
            result.append(HealthWorkout(id: workout.uuid, start: workout.startDate, end: workout.endDate, sourceName: Self.sourceName(workout), isOwn: isOwn,
                                        sessionID: isOwn ? sessionID : nil, activityName: Self.activityName(workout.workoutActivityType),
                                        activeKcal: kcal.flatMap { $0 > 0 ? $0 : nil }, averageHeartRate: rate.flatMap { (20...300).contains($0) ? $0 : nil },
                                        energySegments: segments))
        }
        return result
    }

    /// Saves a workout for part or all of a session, tagged with the session so Lifting can find it again.
    func save(_ request: HealthSave) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(request.activity)
        configuration.locationType = request.activity == .strength ? .indoor : .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: request.start)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: request.sessionID.uuidString])
        try await builder.endCollection(at: request.end)
        guard let workout = try await builder.finishWorkout() else { throw TrainingError.invalid("Apple Health did not save the workout.") }
        return workout.uuid
    }

    /// Deletes workouts Lifting saved. Anything from another source is skipped, even if asked for.
    func delete(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObjects(with: Set(ids)))], sortDescriptors: [])
        let own = HKSource.default().bundleIdentifier
        let mine = try await descriptor.result(for: store).filter { $0.sourceRevision.source.bundleIdentifier == own }
        if !mine.isEmpty { try await store.delete(mine) }
    }

    private func energySegments(of workout: HKWorkout) async throws -> [HealthSegment] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: energy, predicate: HKQuery.predicateForObjects(from: workout))], sortDescriptors: [SortDescriptor(\.startDate)], limit: 10_000)
        return try await descriptor.result(for: store).map { HealthSegment(start: $0.startDate, end: $0.endDate, kcal: $0.quantity.doubleValue(for: .kilocalorie())) }
    }

    private func averageHeartRate(from start: Date, to end: Date) async throws -> Double? {
        let samples = HKSamplePredicate.quantitySample(type: heartRate, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate))
        return try await HKStatisticsQueryDescriptor(predicate: samples, options: .discreteAverage).result(for: store)?.averageQuantity()?.doubleValue(for: Self.bpm)
    }

    private static func sourceName(_ workout: HKWorkout) -> String {
        if workout.device?.model == "Watch" || workout.sourceRevision.productType?.hasPrefix("Watch") == true { return "Apple Watch" }
        return workout.sourceRevision.source.name
    }

    private static func activityType(_ activity: HealthActivity) -> HKWorkoutActivityType {
        switch activity {
        case .strength: return .traditionalStrengthTraining
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .stairs: return .stairClimbing
        case .elliptical: return .elliptical
        case .swimming: return .swimming
        case .mixedCardio: return .mixedCardio
        }
    }

    private static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: return "Strength training"
        case .functionalStrengthTraining: return "Functional strength training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross training"
        case .coreTraining: return "Core training"
        case .walking: return "Walk"
        case .running: return "Run"
        case .cycling: return "Cycling"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .mixedCardio: return "Cardio"
        case .swimming: return "Swim"
        default: return "Workout"
        }
    }
}

/// Workouts entered by hand in the Health app may carry calories only in the older total-energy field.
private protocol LegacyWorkoutEnergySource { var totalEnergyBurned: HKQuantity? { get } }
extension HKWorkout: LegacyWorkoutEnergySource {}
private enum LegacyWorkoutEnergy {
    static func kilocalories(_ workout: HKWorkout) -> Double? {
        (workout as LegacyWorkoutEnergySource).totalEnergyBurned?.doubleValue(for: .kilocalorie())
    }
}

extension AppStore {
    var healthSettings: HealthSettings { data.settings.health ?? HealthSettings() }

    /// Starts watching Apple Health when reading is on, then matches recent workouts.
    func startHealth() async {
        guard let health, healthSettings.read else { return }
        health.observe { [weak self] in Task { @MainActor in await self?.refreshHealth() } }
        await refreshHealth()
    }

    func setHealthRead(_ on: Bool) async {
        guard let health else { return }
        if on {
            do { try await health.requestAccess(write: false) } catch { self.error = error.localizedDescription; return }
            perform { d in var value = d.settings.health ?? HealthSettings(); value.read = true; d.settings.health = value }
            await startHealth()
        } else {
            health.stopObserving()
            perform { d in d.settings.health = HealthSettings() }
        }
    }

    func setHealthWrite(_ on: Bool) async {
        guard let health else { return }
        if on {
            do { try await health.requestAccess(write: true) } catch { self.error = error.localizedDescription; return }
            guard health.canSave else { self.error = "Allow Lifting to save workouts in the Health app, under Sharing > Apps > Lifting."; return }
            perform { d in var value = d.settings.health ?? HealthSettings(read: true); value.write = true; value.writeSince = Date(); d.settings.health = value }
            await refreshHealth()
        } else {
            perform { d in var value = d.settings.health ?? HealthSettings(); value.write = false; value.writeSince = nil; d.settings.health = value }
        }
    }

    /// Matches recent sessions with Apple Health, removes Lifting copies that duplicate another recording,
    /// and saves copies that are due. Runs again if Health changes while it works.
    func refreshHealth() async {
        guard let health, healthSettings.read, !storageBlocked else { return }
        if healthRefreshing { healthRefreshPending = true; return }
        healthRefreshing = true
        defer { healthRefreshing = false }
        repeat {
            healthRefreshPending = false
            let now = Date()
            guard let range = data.healthRange(now: now) else { return }
            let windows = data.healthWindows(now: now)
            do {
                let workouts = try await health.workouts(in: range, near: windows)
                var plan = HealthPlan()
                let delay = healthSaveDelay
                guard perform({ plan = $0.reconcileHealth(workouts, now: now, saveDelay: delay) }) else { return }
                if !plan.deletions.isEmpty { try await health.delete(plan.deletions) }
                for request in plan.saves {
                    let saved = try await health.save(request)
                    perform { $0.recordSavedHealthWorkout(saved, for: request.sessionID) }
                }
                healthStatus = nil
            } catch {
                healthStatus = error.localizedDescription
                return
            }
        } while healthRefreshPending
    }

    /// Checks right after a workout and again once Lifting may save its own copy.
    func scheduleHealthCheck() {
        guard health != nil, healthSettings.read else { return }
        Task { [weak self] in
            await self?.refreshHealth()
            guard let delay = self?.healthSaveDelay, (try? await Task.sleep(for: .seconds(delay + 5))) != nil else { return }
            await self?.refreshHealth()
        }
    }

    /// Removes the workouts Lifting saved for a deleted session.
    func deleteHealthCopies(_ workoutIDs: [UUID]) {
        guard let health, !workoutIDs.isEmpty else { return }
        Task { try? await health.delete(workoutIDs) }
    }
}
#else
extension AppStore {
    func startHealth() async {}
    func refreshHealth() async {}
    func scheduleHealthCheck() {}
    func deleteHealthCopies(_ workoutIDs: [UUID]) {}
}
#endif
