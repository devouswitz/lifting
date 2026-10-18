#if !STANDALONE_CHECKS
import XCTest
@testable import LiftingCore
#else
import Foundation
#endif

final class TrainingTests: XCTestCase {
    func testSubstitutionKeepsPendingMyoAndDropStructure() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises.last!
        try data.applyTechnique(to: item.id, plans: SetTechniques.myo(miniSets: 3, rest: 15), isDrop: false, replaceRemaining: true, saveFuture: false)
        let activation = data.activeSession!.exercises.last!.sets[0]
        try data.toggleSet(exerciseID: item.id, setID: activation.id)
        let alternate = data.exercises.first { $0.name == "Dumbbell lateral raise" }!
        try data.substitute(sessionExerciseID: item.id, with: alternate.id, future: false)
        let replacement = data.activeSession!.exercises.last!
        XCTAssertEqual(replacement.sets.count, 3)
        XCTAssertTrue(replacement.sets.allSatisfy { $0.plan.kind == .myoMini })
        XCTAssertEqual(replacement.sets[0].plan.restSeconds, 15)
        XCTAssertEqual(replacement.sets[0].reps, 5)
        XCTAssertNotNil(data.activeSession!.exercises[data.activeSession!.exercises.count - 2].sets[0].completedAt)
        XCTAssertNoThrow(try data.validated())
    }

    func testLiveWorkingWeightRecalculatesPendingWarmupsAndKeepsCompletedAndOtherDays() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises[0]
        let originalWeight = item.sets[0].weight
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        let before = data.variant(item.variantID)!
        try data.setWorkingWeight(100, for: item.id, saveFuture: false)
        XCTAssertEqual(data.activeSession!.exercises[0].sets[0].weight, originalWeight)
        XCTAssertEqual(data.activeSession!.exercises[0].sets[2].weight, 100)
        XCTAssertEqual(data.activeSession!.exercises[0].sets[1].weight!, floor(75 / before.rounding) * before.rounding, accuracy: 0.00001)
        XCTAssertEqual(data.variant(item.variantID), before)
        try data.setWorkingWeight(110, for: item.id, saveFuture: true)
        XCTAssertEqual(data.variant(item.variantID)!.workingWeight, 110)
        XCTAssertThrowsError(try data.setWorkingWeight(.nan, for: item.id, saveFuture: true))
    }
    func testLiveDropUsesActualLoadAndLeavesRoutineAlone() throws {
        var data = TrainingData.starter()
        let routine = data.routines[0]
        try data.start(routineID: routine.id)
        let e = data.activeSession!.exercises.count - 1
        let item = data.activeSession!.exercises[e]
        data.activeSession!.exercises[e].sets[0].weight = 50
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        let before = data.variants
        let plans = SetTechniques.drops(workingWeight: 50, rounding: 2.5)
        try data.applyTechnique(to: item.id, plans: plans, isDrop: true, replaceRemaining: false, saveFuture: false)
        XCTAssertEqual(data.variants, before)
        XCTAssertEqual(data.activeSession!.exercises[e].sets.last!.plan.kind, .drop)
        let rounding = data.variant(item.variantID)!.rounding
        XCTAssertEqual(data.activeSession!.exercises[e].sets.last!.weight!, floor(40 / rounding) * rounding, accuracy: 0.00001)
        XCTAssertEqual(data.activeSession!.exercises[e].sets[2].plan.restSeconds, 0)
        XCTAssertNil(data.restDeadline)
        XCTAssertNoThrow(try data.validated())
    }

    func testMyoReplacementKeepsCompletedSetsAndOnlyUpdatesVariantWhenRequested() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        let e = data.activeSession!.exercises.count - 1
        let item = data.activeSession!.exercises[e]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        let otherID = data.routines[2].slots[1].variantID
        let other = data.variant(otherID)
        let plans = SetTechniques.myo(miniSets: 3, rest: 15)
        try data.applyTechnique(to: item.id, plans: plans, isDrop: false, replaceRemaining: true, saveFuture: true)
        XCTAssertEqual(data.activeSession!.exercises[e].sets.count, 5)
        XCTAssertNotNil(data.activeSession!.exercises[e].sets[0].completedAt)
        XCTAssertEqual(data.variant(item.variantID)!.sets.count, 4)
        XCTAssertEqual(data.variant(otherID), other)
        try data.addSessionSet(to: item.id)
        XCTAssertEqual(data.activeSession!.exercises[e].sets.count, 6)
        XCTAssertEqual(data.activeSession!.exercises[e].sets[4].plan.restSeconds, 15)
        XCTAssertNil(data.activeSession!.exercises[e].sets[5].plan.restSeconds)
        XCTAssertEqual(data.activeSession!.exercises[e].sets[5].plan.kind, .myoMini)
        XCTAssertNoThrow(try data.validated())
    }

    func testMyoAndDropVolumeIncludedAndWarmupsExcluded() throws {
        var data = TrainingData.starter()
        let id = data.routines[0].slots[0].variantID
        let v = data.variants.firstIndex { $0.id == id }!
        data.variants[v].workingWeight = 100; data.variants[v].rounding = 1
        data.variants[v].sets = [SetPlan(kind: .warmup, load: .percent, percent: 50, reps: 10, repCeiling: nil)] + SetTechniques.myo(activationReps: 15, miniReps: 5, miniSets: 2) + SetTechniques.drops(workingWeight: 100, rounding: 1, reps: 10)
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises[0]
        for set in item.sets { try data.toggleSet(exerciseID: item.id, setID: set.id) }
        try data.finish()
        XCTAssertEqual(data.points(exerciseID: item.exerciseID, metric: .volume).first?.value, 3300)
        XCTAssertEqual(data.points(exerciseID: item.exerciseID, metric: .reps).first?.value, 35)
    }

    func testPersistedCardioStopwatchAndMyoState() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[1].id)
        let i = data.activeSession!.exercises.count - 1
        data.activeSession!.exercises[i].timerStartedAt = Date(timeIntervalSince1970: 1000)
        data.activeSession!.exercises[i].timerElapsed = 20
        let restored = try LocalRepository.decode(LocalRepository.encode(data))
        XCTAssertEqual(restored.activeSession!.exercises[i].timerStartedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(restored.activeSession!.exercises[i].timerElapsed, 20)
        XCTAssertThrowsError(try data.applyTechnique(to: data.activeSession!.exercises[i].id, plans: SetTechniques.myo(), isDrop: false, replaceRemaining: true, saveFuture: false))
    }
    func testDropsRemainRelativeAndMyoRestOverrides() throws {
        let drops = SetTechniques.drops(workingWeight: 50, rounding: 2.5, count: 2)
        XCTAssertEqual(drops.count, 2)
        XCTAssertEqual(drops[0].kind, .drop)
        XCTAssertEqual(drops[0].resolvedWeight(working: 50, increment: 2.5), 40)
        XCTAssertEqual(drops[1].resolvedWeight(working: 50, increment: 2.5), 30)
        XCTAssertEqual(drops[0].resolvedWeight(working: 100, increment: 2.5), 80)
        let myo = SetTechniques.myo(activationReps: 20, miniReps: 4, miniSets: 3, rest: 15)
        XCTAssertEqual(myo.count, 4)
        XCTAssertEqual(myo[0].kind, .myoActivation)
        XCTAssertEqual(myo[1].kind, .myoMini)
        XCTAssertEqual(myo[0].reps, 20)
        XCTAssertEqual(myo[1].reps, 4)
        XCTAssertNil(myo.last!.restSeconds)
        var data = TrainingData.starter()
        let id = data.routines[0].slots.last!.variantID
        let v = data.variants.firstIndex { $0.id == id }!
        data.variants[v].sets = myo
        let now = Date(timeIntervalSince1970: 1000)
        try data.start(routineID: data.routines[0].id, now: now)
        let item = data.activeSession!.exercises.last!
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id, now: now)
        XCTAssertEqual(data.restDeadline, now.addingTimeInterval(15))
        try data.finish(now: now.addingTimeInterval(100))
        XCTAssertNoThrow(try LocalRepository.decode(LocalRepository.encode(data)))
    }
    func testVariantsAreIndependentAndSnapshotsDoNotChange() throws {
        var data = TrainingData.starter()
        let upper = data.routines[0], push = data.routines[2]
        let upperID = upper.slots.last!.variantID, pushID = push.slots[1].variantID
        XCTAssertNotEqual(upperID, pushID)
        XCTAssertEqual(data.variant(upperID)?.exerciseID, data.variant(pushID)?.exerciseID)
        try data.start(routineID: upper.id)
        let snapshot = data.activeSession!
        data.variants[data.variants.firstIndex { $0.id == upperID }!].workingWeight = 999
        XCTAssertEqual(data.activeSession, snapshot)
        XCTAssertEqual(data.variant(pushID)?.workingWeight, WeightUnit.lb.kilograms(15))
        XCTAssertNoThrow(try data.validated())
    }

    func testPercentWarmupAndMixedTargets() throws {
        let plan = SetPlan(kind: .warmup, load: .percent, percent: 65, reps: 5, repCeiling: nil, seconds: 30, rpe: 4)
        XCTAssertEqual(plan.resolvedWeight(working: 100, increment: 2.5), 65)
        XCTAssertEqual(plan.resolvedWeight(working: 95, increment: 2.5), 60)
        let v = Variant(exerciseID: UUID(), label: "Test", workingWeight: 100, rounding: 2.5, sets: [plan])
        let set = LoggedSet(plan: plan, variant: v)
        XCTAssertEqual(set.rpe, 4); XCTAssertEqual(set.seconds, 30); XCTAssertEqual(set.reps, 5)
    }

    func testSubstitutionPreservesLoggedSetsAndDayScope() throws {
        var data = TrainingData.starter()
        let routine = data.routines[0]
        try data.start(routineID: routine.id)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        let target = data.exercises.first { $0.name == "Incline dumbbell press" }!
        try data.substitute(sessionExerciseID: item.id, with: target.id, future: false)
        XCTAssertEqual(data.activeSession!.exercises[0].sets.count, 1)
        XCTAssertNotNil(data.activeSession!.exercises[0].sets[0].completedAt)
        XCTAssertEqual(data.activeSession!.exercises[1].exerciseID, target.id)
        XCTAssertEqual(data.activeSession!.exercises[1].sets.count, 4)
        XCTAssertFalse(data.activeSession!.exercises[0].progressionEligible)
        XCTAssertFalse(data.activeSession!.exercises[1].progressionEligible)
        XCTAssertEqual(data.routines[0], routine)
        XCTAssertNoThrow(try data.validated())
    }

    func testFutureSubstitutionOnlyChangesThisSlot() throws {
        var data = TrainingData.starter()
        let original = data.routines
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises.last!
        let target = data.exercises.first { $0.name == "Dumbbell lateral raise" }!
        try data.substitute(sessionExerciseID: item.id, with: target.id, future: true)
        XCTAssertNotEqual(data.routines[0].slots.last!.variantID, original[0].slots.last!.variantID)
        XCTAssertEqual(data.routines[2], original[2])
        XCTAssertNotEqual(data.activeSession!.exercises.last!.variantID, item.variantID)
        XCTAssertEqual(data.activeSession!.exercises.last!.sets[0].weight, 0)
    }

    func testCardioCanLiveAlongsideStrength() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[1].id)
        let run = data.activeSession!.exercises.last!
        XCTAssertEqual(run.mode, .cardio)
        XCTAssertEqual(run.sets[0].seconds, 1200)
        XCTAssertNil(run.sets[0].weight)
        try data.toggleSet(exerciseID: run.id, setID: run.sets[0].id)
        try data.finish()
        XCTAssertEqual(data.points(exerciseID: run.exerciseID, metric: .duration).first?.value, 20)
        XCTAssertTrue(data.points(exerciseID: run.exerciseID, metric: .estimatedMax).isEmpty)
    }

    func testProgressionIsVariantSpecificAndWarmupsExcluded() throws {
        var data = TrainingData.starter()
        let id = data.routines[0].slots.last!.variantID
        let otherID = data.routines[2].slots[1].variantID
        let i = data.variants.firstIndex { $0.id == id }!
        data.variants[i].progression.mode = .double
        let before = data.variants[i].workingWeight
        let other = data.variant(otherID)!
        try data.start(routineID: data.routines[0].id)
        let exercise = data.activeSession!.exercises.last!
        for set in exercise.sets { try data.toggleSet(exerciseID: exercise.id, setID: set.id) }
        try data.finish()
        XCTAssertEqual(data.variants[i].workingWeight, before + data.variants[i].progression.increment)
        XCTAssertEqual(data.variant(otherID), other)
        let points = data.points(exerciseID: exercise.exerciseID, variantID: id, metric: .volume)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, before * 45, accuracy: 0.001)
        XCTAssertTrue(data.points(exerciseID: exercise.exerciseID, variantID: otherID, metric: .weight).isEmpty)
    }

    func testDoubleProgressionWithinRangeDoesNotDeload() throws {
        var data = TrainingData.starter()
        let id = data.routines[0].slots.last!.variantID
        let i = data.variants.firstIndex { $0.id == id }!
        data.variants[i].progression.mode = .double
        data.variants[i].progression.deloadAfter = 1
        let before = data.variants[i].workingWeight
        try data.start(routineID: data.routines[0].id)
        let e = data.activeSession!.exercises.count - 1
        for s in data.activeSession!.exercises[e].sets.indices {
            data.activeSession!.exercises[e].sets[s].reps = 12
            let item = data.activeSession!.exercises[e]
            try data.toggleSet(exerciseID: item.id, setID: item.sets[s].id)
        }
        try data.finish()
        XCTAssertEqual(data.variants[i].workingWeight, before)
        XCTAssertEqual(data.variants[i].progression.failures, 0)
    }

    func testFailureDeloadAndPartialSessionDoesNotProgress() throws {
        var data = TrainingData.starter()
        let id = data.routines[0].slots[0].variantID
        let i = data.variants.firstIndex { $0.id == id }!
        data.variants[i].progression.mode = .linear; data.variants[i].progression.deloadAfter = 1
        let before = data.variants[i].workingWeight
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises[0]
        for s in item.sets.indices {
            data.activeSession!.exercises[0].sets[s].reps = 2
            try data.toggleSet(exerciseID: item.id, setID: item.sets[s].id)
        }
        try data.finish()
        XCTAssertLessThan(data.variants[i].workingWeight, before)
        let after = data.variants[i].workingWeight
        try data.start(routineID: data.routines[0].id)
        let next = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: next.id, setID: next.sets[0].id)
        try data.finish()
        XCTAssertEqual(data.variants[i].workingWeight, after)
    }

    func testRestDeadlineAndUndo() throws {
        var data = TrainingData.starter()
        let now = Date(timeIntervalSince1970: 1000)
        try data.start(routineID: data.routines[0].id, now: now)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id, now: now)
        XCTAssertEqual(data.restDeadline, now.addingTimeInterval(Double(item.restSeconds)))
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        XCTAssertNil(data.restDeadline)
        XCTAssertThrowsError(try data.finish())
    }

    func testAtomicRoundTripActiveRecoveryAndCorruptionFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = LocalRepository(url: dir.appendingPathComponent("data.json"))
        var data = TrainingData.starter()
        try repo.save(data)
        try data.start(routineID: data.routines[0].id)
        try repo.save(data)
        let restored = try XCTUnwrap(repo.load())
        XCTAssertEqual(restored.data.activeSession?.id, data.activeSession?.id)
        XCTAssertFalse(restored.recoveredBackup)
        try Data("broken".utf8).write(to: repo.url)
        XCTAssertTrue(try XCTUnwrap(repo.load()).recoveredBackup)
        XCTAssertNil(try XCTUnwrap(repo.load()).data.activeSession)
        try Data("broken".utf8).write(to: repo.backupURL)
        XCTAssertThrowsError(try repo.load())
    }

    func testBackupRejectsBadReferencesVersionsAndValues() throws {
        var data = TrainingData.starter()
        data.schemaVersion = 2
        XCTAssertThrowsError(try data.validated())
        data.schemaVersion = 1; data.variants[0].exerciseID = UUID()
        XCTAssertThrowsError(try data.validated())
        data = .starter(); data.variants[0].sets[0].rpe = 11
        XCTAssertThrowsError(try data.validated())
        data = .starter(); data.variants[0].sets[0].repCeiling = -1
        XCTAssertThrowsError(try data.validated())
        data = .starter(); data.exercises.append(data.exercises[0])
        XCTAssertThrowsError(try data.validated())
        data = .starter(); data.variants[0].sets[0].fixedWeight = .nan
        XCTAssertThrowsError(try data.validated())
    }

    func testCSVQuotesNotesAndDefusesFormulas() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        data.activeSession!.exercises[0].notes = "=1+1\n\"quoted\", note"
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        try data.finish()
        let csv = String(data: LocalRepository.csv(data), encoding: .utf8)!
        XCTAssertTrue(csv.contains("'=1+1")); XCTAssertTrue(csv.contains("\"\"quoted\"\""))
    }

    func testPlateMathAndUnitRoundTrip() {
        let result = PlateCalculator.plates(total: 225, bar: 45, available: [45, 25, 10, 5, 2.5])
        XCTAssertEqual(result.plates, [45, 45]); XCTAssertEqual(result.remainder, 0)
        XCTAssertEqual(WeightUnit.lb.display(WeightUnit.lb.kilograms(135)), 135, accuracy: 0.00001)
    }

    func testDemoUsesSameValidatedModelAndGraphFilters() throws {
        let data = TrainingData.demo()
        XCTAssertEqual(data.sessions.count, 30)
        XCTAssertNoThrow(try data.validated())
        let exercise = data.exercises.first { $0.name == "Cable lateral raise" }!
        let variants = data.variants.filter { $0.exerciseID == exercise.id }
        XCTAssertEqual(data.points(exerciseID: exercise.id, metric: .weight).count, 20)
        XCTAssertEqual(data.points(exerciseID: exercise.id, variantID: variants[0].id, metric: .weight).count, 10)
        let bytes = try LocalRepository.encode(data)
        XCTAssertEqual(try LocalRepository.decode(bytes).sessions.count, 30)
    }
}
