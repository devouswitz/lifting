#if !STANDALONE_CHECKS
import XCTest
@testable import LiftingCore
#else
import Foundation
#endif

final class TrainingTests: XCTestCase {
    func testTimedStrengthImportsRemainStrengthAndMatchCatalog() throws {
        let bytes = CSVCodec.render([["title", "start_time", "exercise_title", "duration_seconds", "weight_kg", "reps"],
            ["Upper", "2026-10-18T10:00:00Z", "Plank", "60", "", ""],
            ["Upper", "2026-10-18T10:00:00Z", "Bench Press (Barbell)", "30", "60", "8"]])
        let bundle = try ExternalHistoryCSV.decode(bytes, options: ExternalHistoryCSV.detect(try CSVCodec.parse(bytes)[0]))
        let items = bundle.content.sessions[0].exercises
        XCTAssertEqual(items[0].mode, .bodyweight); XCTAssertEqual(items[1].mode, .strength)
        var local = TrainingData.starter(); try local.importHistory(bundle)
        XCTAssertEqual(local.muscleSummary().reduce(0) { $0 + $1.directSets }, 2)
        XCTAssertEqual(local.muscleSummary().first { $0.name == "Chest" }?.volume, 480)
    }
    func testFailureTagUsesCompletedRepsForProgression() throws {
        for reps in [4, 5] {
            var data = TrainingData.starter(); let day = data.dayTemplates[0], v = data.variants.firstIndex { $0.id == day.slots[0].variantID }!
            data.variants[v].sets = [SetPlan(kind: .failure, reps: 5, repCeiling: nil)]
            data.variants[v].progression.mode = .linear; data.variants[v].workingWeight = 100
            try data.start(routineID: day.id)
            let item = data.activeSession!.exercises[0]
            data.activeSession!.exercises[0].sets[0].reps = reps
            try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id); try data.finish()
            XCTAssertEqual(data.variants[v].workingWeight, reps == 5 ? 100 + data.variants[v].progression.increment : 100)
        }
    }
    func testNamedWarmupPresetsApplyIndependentCopiesAndKeepCompletedSets() throws {
        var data = TrainingData.starter()
        let preset = WarmupPreset(name: "Descending", sets: [80.0, 60, 40].map { SetPlan(kind: .warmup, load: .percent, percent: $0, reps: 5, repCeiling: 8, rpe: 6) })
        try data.saveWarmupPreset(preset)
        let day = data.dayTemplates[0], variantID = day.slots[0].variantID
        let originalWork = data.variant(variantID)!.sets.filter { $0.kind != .warmup }
        try data.applyWarmupPreset(preset.id, toVariants: [variantID])
        XCTAssertEqual(data.variant(variantID)!.sets.prefix(3).map(\.percent), [80, 60, 40])
        XCTAssertEqual(data.variant(variantID)!.sets.filter { $0.kind != .warmup }, originalWork)
        XCTAssertTrue(Set(data.variant(variantID)!.sets.map(\.id)).isDisjoint(with: Set(preset.sets.map(\.id))))
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        let completed = data.activeSession!.exercises[0].sets[0]
        try data.applyWarmupPreset(preset.id, toSessionExercises: [item.id], replacing: true, saveFuture: false)
        let live = data.activeSession!.exercises[0]
        XCTAssertEqual(live.sets.first?.id, completed.id); XCTAssertEqual(live.sets.first?.completedAt, completed.completedAt)
        XCTAssertEqual(live.sets.filter { $0.plan.kind == .warmup && $0.completedAt == nil }.count, 3)
        XCTAssertNil(live.sets.first { $0.completedAt == nil }?.reps)
        XCTAssertEqual(data.variant(variantID)!.sets.filter { $0.kind == .warmup }.count, 3)
        var edited = preset; edited.sets[0].percent = 25; try data.saveWarmupPreset(edited)
        XCTAssertEqual(data.variant(variantID)!.sets[0].percent, 80)
        XCTAssertEqual(try LocalRepository.decode(LocalRepository.encode(data)).warmupPresets[0].sets[0].percent, 25)
    }

    func testWarmupPresetSyncAndFutureScope() throws {
        var a = TrainingData.starter(), state = DeviceSyncState()
        let preset = WarmupPreset(name: "RPE only", sets: [SetPlan(kind: .warmup, load: .none, reps: nil, repCeiling: nil, rpe: 5)])
        try a.saveWarmupPreset(preset)
        let day = a.dayTemplates[0]
        try a.start(routineID: day.id)
        let item = a.activeSession!.exercises[0], otherVariant = day.slots[1].variantID, original = a.variant(otherVariant)!
        try a.applyWarmupPreset(preset.id, toSessionExercises: [item.id], replacing: true, saveFuture: true)
        XCTAssertEqual(a.variant(item.variantID)!.sets[0].rpe, 5); XCTAssertNil(a.variant(item.variantID)!.sets[0].reps)
        XCTAssertEqual(a.variant(otherVariant), original)
        try state.capture(a)
        var receiver = DeviceSyncState(); let b = try receiver.merge([state], into: TrainingData())
        XCTAssertEqual(b.warmupPresets, a.warmupPresets)
        XCTAssertNil(b.activeSession)
        XCTAssertNoThrow(try b.validated())
    }

    func testNestedJSONAndFitNotesImportsUseTheSameValidatedPipeline() throws {
        let json = Data("""
        {"workouts":[{"id":"abc","title":"Lower","start_time":"2026-10-18T09:00:00Z","end_time":"2026-10-18T10:00:00Z","exercises":[{"title":"Run","sets":[{"type":"normal","distance_meters":2500,"duration_seconds":900,"rpe":7}]}]}]}
        """.utf8)
        let bytes = try ExternalHistoryJSON.csv(json), options = ExternalHistoryCSV.detect(try CSVCodec.parse(bytes)[0])
        let imported = try ExternalHistoryCSV.decode(bytes, options: options).content
        XCTAssertEqual(imported.sessions[0].exercises[0].sets[0].meters, 2500)
        XCTAssertEqual(imported.sessions[0].exercises[0].sets[0].seconds, 900)
        let fit = CSVCodec.render([["Date", "Exercise", "Category", "Weight", "Weight Unit", "Reps", "Distance", "Distance Unit", "Time", "Comment"], ["2026-10-18", "Curl", "Biceps", "10", "kg", "8", "", "", "", "note"]])
        let fitOptions = ExternalHistoryCSV.detect(try CSVCodec.parse(fit)[0])
        XCTAssertEqual(fitOptions.source, "FitNotes")
        let fitBundle = try ExternalHistoryCSV.decode(fit, options: fitOptions)
        XCTAssertEqual(fitBundle.content.sessions[0].exercises[0].muscle, "Biceps")
        XCTAssertThrowsError(try ExternalHistoryJSON.csv(Data("{\"schemaVersion\":1}".utf8)))
    }

    func testForeignImportMatchesKnownEquipmentAndKeepsDayTracksSeparate() throws {
        let bytes = CSVCodec.render([["Date", "Workout Name", "Exercise Name", "Weight", "Reps"],
            ["2026-10-18", "Upper", "Bench Press (Barbell)", "40", "8"], ["2026-10-19", "Push", "Bench Press (Barbell)", "50", "5"]])
        let bundle = try ExternalHistoryCSV.decode(bytes, options: ExternalHistoryCSV.detect(try CSVCodec.parse(bytes)[0]))
        var local = TrainingData.starter()
        let bench = local.exercises.first { $0.name == "Bench press" }!
        try local.importHistory(bundle)
        XCTAssertEqual(Set(local.sessions.flatMap(\.exercises).map(\.exerciseID)), [bench.id])
        XCTAssertEqual(Set(local.sessions.flatMap(\.exercises).map(\.variantID)).count, 2)
        XCTAssertEqual(local.muscleSummary().first?.name, "Chest")
    }

    func testLinkedFlowWarmupsRoundsUnevenSetsAndDropChains() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0], ids = Set(day.slots.prefix(2).map(\.id))
        try data.linkRoutineExercises(routineID: day.id, slots: ids, rest: 75, transition: 5)
        for slot in day.slots.prefix(2) {
            let i = data.variants.firstIndex { $0.id == slot.variantID }!
            data.variants[i].sets = [SetPlan(reps: 8, repCeiling: nil), SetPlan(reps: 8, repCeiling: nil)]
        }
        let first = data.variants.firstIndex { $0.id == day.slots[0].variantID }!
        data.variants[first].sets.insert(SetPlan(kind: .warmup, reps: 5, repCeiling: nil), at: 0)
        data.variants[first].sets.insert(SetPlan(kind: .drop, reps: 8, repCeiling: nil, restSeconds: 0), at: 2)
        data.variants[first].sets.append(SetPlan(reps: 8, repCeiling: nil))
        try data.start(routineID: day.id)
        let a = data.activeSession!.exercises[0], b = data.activeSession!.exercises[1], now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(data.activeSession!.linkTitle(for: a.id), "Superset")
        try data.toggleSet(exerciseID: a.id, setID: a.sets[0].id, now: now)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, false)
        try data.toggleSet(exerciseID: a.id, setID: a.sets[1].id, now: now)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, false)
        try data.toggleSet(exerciseID: a.id, setID: a.sets[2].id, now: now)
        XCTAssertEqual(data.activeSession!.exercises[1].collapsed, false)
        XCTAssertEqual(data.restDeadline, now.addingTimeInterval(5))
        try data.toggleSet(exerciseID: b.id, setID: b.sets[0].id, now: now)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, false)
        XCTAssertEqual(data.restDeadline, now.addingTimeInterval(75))
        try data.toggleSet(exerciseID: a.id, setID: a.sets[3].id, now: now)
        try data.toggleSet(exerciseID: b.id, setID: b.sets[1].id, now: now)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, false)
        XCTAssertEqual(data.restDeadline, now.addingTimeInterval(75))
        try data.toggleSet(exerciseID: a.id, setID: a.sets[4].id, now: now)
        XCTAssertNoThrow(try data.validated())
        try data.toggleSet(exerciseID: b.id, setID: b.sets[1].id, now: now)
        XCTAssertNil(data.restDeadline)
    }

    func testCircuitSettingsSurviveCopiesCSVAndSubstitution() throws {
        var data = TrainingData.starter(); let day = data.dayTemplates[0]
        try data.linkRoutineExercises(routineID: day.id, slots: Set(day.slots.map(\.id)), rest: 63, transition: 7)
        let copyID = try data.saveDayAsTemplate(day.id)
        XCTAssertEqual(data.routine(copyID)!.slots[0].groupRestSeconds, 63)
        let csv = try RoutineCSV.decode(RoutineCSV.export(data, dayID: day.id)).content
        XCTAssertEqual(csv.routines[0].slots[0].transitionSeconds, 7)
        var imported = TrainingData(); try imported.importRoutines(RoutineBundle(content: csv))
        XCTAssertEqual(imported.routines[0].slots[0].groupRestSeconds, 63)
        try data.start(routineID: day.id)
        let first = data.activeSession!.exercises[0]
        XCTAssertEqual(data.activeSession!.linkTitle(for: first.id), "Circuit")
        let alternate = data.exercises.first { $0.name == "Dumbbell lateral raise" }!
        try data.substitute(sessionExerciseID: first.id, with: alternate.id, future: false)
        XCTAssertEqual(data.activeSession!.exercises[0].group, first.group)
        XCTAssertEqual(data.activeSession!.exercises[0].groupRestSeconds, 63)
        XCTAssertEqual(try LocalRepository.decode(LocalRepository.encode(data)).activeSession!.exercises[0].transitionSeconds, 7)
        data.unlinkSessionGroup(first.group!, saveFuture: true)
        XCTAssertTrue(data.activeSession!.exercises.allSatisfy { $0.group == nil })
        XCTAssertTrue(data.routine(day.id)!.slots.allSatisfy { $0.group.isEmpty })
        XCTAssertFalse(data.routine(copyID)!.slots[0].group.isEmpty)
    }

    func testMuscleAnalyticsUsesCompletedSnapshotsAndNoInventedVolume() throws {
        var data = TrainingData.starter(); let day = data.dayTemplates[0]
        let exerciseID = data.variant(day.slots[0].variantID)!.exerciseID
        let e = data.exercises.firstIndex { $0.id == exerciseID }!
        data.exercises[e].secondaryMuscles = ["Triceps", "Chest", "triceps"]
        try data.start(routineID: day.id)
        var session = data.activeSession!; session.endedAt = session.startedAt
        session.exercises = [session.exercises[0]]
        for s in session.exercises[0].sets.indices {
            session.exercises[0].sets[s].completedAt = session.startedAt
            session.exercises[0].sets[s].weight = 100; session.exercises[0].sets[s].reps = s == 2 ? nil : 5
        }
        data.sessions = [session]; data.activeSession = nil
        data.exercises[e].muscle = "Renamed later"
        let result = data.muscleSummary()
        let chest = result.first { $0.name == "Chest" }!, triceps = result.first { $0.name == "Triceps" }!
        XCTAssertEqual(chest.directSets, 3); XCTAssertEqual(chest.volume, 1000)
        XCTAssertEqual(triceps.secondarySets, 3); XCTAssertEqual(triceps.setCount(includeSecondary: true), 1.5)
        XCTAssertTrue(data.muscleSummary(since: session.startedAt.addingTimeInterval(1)).isEmpty)
        XCTAssertTrue(data.muscleSummary(programID: UUID()).isEmpty)
    }

    func testTechniqueRangesAndRPEOnlyUseSharedTargets() throws {
        let drops = SetTechniques.drops(workingWeight: 100, rounding: 0, reductionPercent: 12.5, count: 2, reps: 12, repCeiling: 15, rpe: 8)
        XCTAssertEqual(drops[0].percent, 87.5); XCTAssertEqual(drops[1].percent, 76.5625)
        XCTAssertEqual(drops[0].repTarget, "12-15"); XCTAssertNil(drops[0].initialReps)
        let myo = SetTechniques.myo(activation: SetPlan(reps: nil, repCeiling: nil, rpe: 9), mini: SetPlan(reps: 3, repCeiling: 5, rpe: 8), miniSets: 3, rest: 17)
        XCTAssertNil(myo[0].reps); XCTAssertEqual(myo[0].rpe, 9)
        XCTAssertEqual(myo[1].repTarget, "3-5"); XCTAssertEqual(myo[1].restSeconds, 17)
    }

    func testStrongImportUnitsTypesNotesAndStableDeduplication() throws {
        let bytes = CSVCodec.render([
            ["Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight", "Reps", "Distance", "Seconds", "Notes", "Workout Notes", "RPE"],
            ["2026-10-18 09:30:00", "Upper", "1h 2m 3s", "Bench press", "W", "45", "5", "", "", "warm", "session", ""],
            ["2026-10-18 09:30:00", "Upper", "1h 2m 3s", "Bench press", "F", "135", "8", "", "", "quoted, note\nsecond line", "session", "9"]])
        var options = ExternalHistoryCSV.detect(try CSVCodec.parse(bytes)[0]); options.weightUnit = .lb
        let bundle = try ExternalHistoryCSV.decode(bytes, options: options)
        let session = bundle.content.sessions[0], sets = session.exercises[0].sets
        XCTAssertEqual(options.source, "Strong"); XCTAssertEqual(session.endedAt!.timeIntervalSince(session.startedAt), 3723)
        XCTAssertEqual(sets[1].weight!, WeightUnit.lb.kilograms(135), accuracy: 0.00001)
        XCTAssertEqual(sets[0].plan.kind, .warmup); XCTAssertEqual(sets[1].plan.kind, .failure)
        XCTAssertEqual(sets[1].sourceFields?["Notes"], "quoted, note\nsecond line")
        var local = TrainingData(); XCTAssertEqual(try local.importHistory(bundle), 1)
        XCTAssertEqual(try local.importHistory(ExternalHistoryCSV.decode(bytes, options: options)), 0)
        try local.createProgramFromHistory(bundle, name: "Migrated")
        XCTAssertEqual(local.activeProgram?.dayIDs.count, 1)
        XCTAssertEqual(local.sessions(inProgram: local.activeProgramID).count, 1)
        XCTAssertEqual(local.activeProgram?.dayIDs.first.flatMap(local.routine)?.slots.count, 1)
        let migratedVariant = local.variant(local.activeProgram!.dayIDs.first.flatMap(local.routine)!.slots[0].variantID)!
        XCTAssertEqual(migratedVariant.workingWeight, WeightUnit.lb.kilograms(135), accuracy: 0.00001)
        XCTAssertEqual(migratedVariant.sets[0].load, .percent)
        let roundTrip = try HistoryCSV.decode(HistoryCSV.export(local)).content
        XCTAssertEqual(roundTrip.sessions[0].exercises[0].sets[1].sourceFields, sets[1].sourceFields)
    }

    func testHevyAndMappedCSVImportPreserveCardioAndRejectBadValues() throws {
        let bytes = CSVCodec.render([
            ["title", "start_time", "end_time", "description", "exercise_title", "superset_id", "exercise_notes", "set_index", "set_type", "weight_kg", "reps", "distance_km", "duration_seconds", "rpe"],
            ["Legs", "18 Oct 2026, 09:00", "18 Oct 2026, 10:00", "Day note", "Run", "", "Exercise note", "0", "normal", "", "", "3.2", "1200", "7"]])
        let options = ExternalHistoryCSV.detect(try CSVCodec.parse(bytes)[0]), bundle = try ExternalHistoryCSV.decode(bytes, options: options)
        let item = bundle.content.sessions[0].exercises[0]
        XCTAssertEqual(options.source, "Hevy"); XCTAssertEqual(item.mode, .cardio)
        XCTAssertEqual(item.sets[0].meters, 3200); XCTAssertEqual(item.sets[0].seconds, 1200); XCTAssertEqual(item.sets[0].rpe, 7)
        let generic = CSVCodec.render([["When", "Move", "Load", "Count"], ["18/10/2026", "Curl", "12,5", "10"]])
        var map = ExternalCSVOptions(columns: [.date: "When", .exercise: "Move", .weight: "Load", .reps: "Count"]); map.dateFormat = "dd/MM/yyyy"
        XCTAssertEqual(try ExternalHistoryCSV.decode(generic, options: map).content.sessions[0].exercises[0].sets[0].weight, 12.5)
        XCTAssertThrowsError(try ExternalHistoryCSV.decode(CSVCodec.render([["When", "Move", "Load", "Count"], ["18/10/2026", "Curl", "nan", "10"]]), options: map))
    }

    func testDeviceSyncMergesIndependentEditsAndKeepsLocalPreferences() throws {
        let original = TrainingData.starter(); var a = original, b = original
        var left = DeviceSyncState(), right = DeviceSyncState()
        try left.capture(original); _ = try right.merge([left], into: original)
        a.routines[0].notes = "A"; b.routines[1].notes = "B"; b.settings.unit = .kg
        try left.capture(a); try right.capture(b)
        a = try left.merge([right], into: a); b = try right.merge([left], into: b)
        XCTAssertEqual(a.routines.first { $0.id == original.routines[0].id }?.notes, "A")
        XCTAssertEqual(a.routines.first { $0.id == original.routines[1].id }?.notes, "B")
        XCTAssertEqual(b.settings.unit, .kg); XCTAssertEqual(a.settings.unit, .lb)
        XCTAssertEqual(left.records, right.records)
        XCTAssertEqual(try DeviceSyncState.decode(left.encoded()), left)
    }

    func testSyncTombstonesAndConcurrentEditsConvergeWithoutResurrection() throws {
        var a = TrainingData.starter(), b = a
        var left = DeviceSyncState(), right = DeviceSyncState()
        try left.capture(a); b = try right.merge([left], into: b)
        let stale = right, removed = a.routines[0].id
        a.removeDay(removed); try left.capture(a)
        b = try right.merge([left], into: b)
        XCTAssertNil(b.routine(removed))
        b = try right.merge([stale], into: b); XCTAssertNil(b.routine(removed))
        let key = a.variants[0].id
        a.variants[0].notes = "left"; b.variants[b.variants.firstIndex { $0.id == key }!].notes = "right"
        try left.capture(a); try right.capture(b)
        a = try left.merge([right], into: a); b = try right.merge([left], into: b)
        XCTAssertEqual(a.variant(key)?.notes, b.variant(key)?.notes)
    }

    func testSyncRejectsBrokenReferencesAtomically() throws {
        var data = TrainingData.starter(), state = DeviceSyncState()
        try state.capture(data)
        var remote = state
        let key = "exercise/\(data.exercises[0].id.uuidString)"
        remote.clock += 1; remote.records[key]!.payload = nil; remote.records[key]!.revision.counter = remote.clock
        let before = state
        XCTAssertThrowsError(try state.merge([remote], into: data))
        XCTAssertEqual(state, before)
        try data.start(routineID: data.dayTemplates[0].id)
        var same = before; let restored = try same.merge([before], into: data)
        XCTAssertEqual(restored.activeSession?.id, data.activeSession?.id)
    }

    func testRepRangesCanBeCompletedWithoutInventingAnActualCount() throws {
        for rule in [LoadRule.none, .working] {
            var data = TrainingData.starter()
            let day = data.dayTemplates[0]
            let id = day.slots[0].variantID
            let v = data.variants.firstIndex { $0.id == id }!
            data.variants[v].workingWeight = 100
            data.variants[v].progression.mode = .double
            data.variants[v].sets = [SetPlan(load: rule, reps: 12, repCeiling: 15)]
            try data.start(routineID: day.id)
            let item = data.activeSession!.exercises[0]
            XCTAssertNil(item.sets[0].reps)
            try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
            try data.finish()
            XCTAssertEqual(data.variant(id)!.workingWeight, 100)
            XCTAssertTrue(data.points(exerciseID: item.exerciseID, metric: .reps).isEmpty)
            XCTAssertTrue(data.points(exerciseID: item.exerciseID, metric: .volume).isEmpty)
            let restored = try LocalRepository.decode(LocalRepository.encode(data))
            XCTAssertEqual(restored.sessions[0].exercises[0].sets[0].plan.repTarget, "12-15")
            XCTAssertNil(restored.sessions[0].exercises[0].sets[0].reps)
            let csv = try HistoryCSV.decode(HistoryCSV.export(data)).content
            XCTAssertNil(csv.sessions[0].exercises[0].sets[0].reps)
            XCTAssertEqual(csv.sessions[0].exercises[0].sets[0].plan.repTarget, "12-15")
            data.sessions[0].exercises[0].sets[0].reps = 14
            XCTAssertEqual(data.points(exerciseID: item.exerciseID, metric: .reps).first?.value, 14)
            XCTAssertEqual(data.sessions[0].exercises[0].sets[0].plan.repTarget, "12-15")
            XCTAssertNoThrow(try data.validated())
        }
    }

    func testAddingAndSubstitutingRangeSetsKeepTargetsSeparateFromActualCounts() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0]
        let v = data.variants.firstIndex { $0.id == day.slots[0].variantID }!
        data.variants[v].sets = [SetPlan(reps: 12, repCeiling: 15)]
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises[0]
        data.activeSession!.exercises[0].sets[0].reps = 13
        try data.addSessionSet(to: item.id)
        XCTAssertEqual(data.activeSession!.exercises[0].sets[0].reps, 13)
        XCTAssertNil(data.activeSession!.exercises[0].sets[1].reps)
        try data.substitute(sessionExerciseID: item.id, with: data.exercises.first { $0.name == "Incline dumbbell press" }!.id, future: false)
        let sets = data.activeSession!.exercises[0].sets
        XCTAssertEqual(sets[0].reps, 13)
        XCTAssertNil(sets[1].reps)
        XCTAssertEqual(sets.map { $0.plan.repTarget }, ["12-15", "12-15"])
        XCTAssertNoThrow(try data.validated())
    }

    func testRPEOnlyTargetsAndLiveRangeEditsRemainIndependent() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0]
        let v = data.variants.firstIndex { $0.id == day.slots[0].variantID }!
        data.variants[v].sets = [SetPlan(load: .none, reps: nil, repCeiling: nil, rpe: 7)]
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises[0]
        XCTAssertNil(item.sets[0].reps)
        XCTAssertNil(item.sets[0].weight)
        try data.replaceSetPlan(exerciseID: item.id, setID: item.sets[0].id, plan: SetPlan(load: .none, reps: 12, repCeiling: 15, rpe: 8))
        XCTAssertNil(data.activeSession!.exercises[0].sets[0].reps)
        try data.substitute(sessionExerciseID: item.id, with: data.exercises.first { $0.name == "Dumbbell lateral raise" }!.id, future: false)
        let replacement = data.activeSession!.exercises[0]
        XCTAssertEqual(replacement.sets[0].plan.repTarget, "12-15")
        XCTAssertNil(replacement.sets[0].reps)
        try data.replaceSetPlan(exerciseID: replacement.id, setID: replacement.sets[0].id, plan: SetPlan(load: .none, reps: nil, repCeiling: nil, rpe: 7))
        try data.toggleSet(exerciseID: replacement.id, setID: replacement.sets[0].id)
        try data.finish()
        XCTAssertEqual(data.points(exerciseID: replacement.exerciseID, metric: .rpe).first?.value, 7)
        XCTAssertTrue(data.points(exerciseID: replacement.exerciseID, metric: .reps).isEmpty)
        XCTAssertNoThrow(try HistoryCSV.decode(HistoryCSV.export(data)))
    }

    func testProgramHistoryFilteringAndTitlesSurviveRenameRemovalAndCSV() throws {
        var data = TrainingData.starter()
        let program = data.activeProgram!
        let dayID = program.dayIDs[0]
        try data.start(routineID: dayID)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        try data.finish()
        let recorded = data.sessions[0]
        XCTAssertEqual(data.title(for: recorded), "Starter - Upper")
        var legacy = recorded; legacy.id = UUID(); legacy.programID = nil; legacy.programName = nil
        var other = recorded; other.id = UUID(); other.programID = UUID(); other.programName = "Other"
        data.sessions += [legacy, other]
        XCTAssertEqual(data.sessions(inProgram: program.id).count, 2)
        XCTAssertEqual(data.sessions(inProgram: other.programID).count, 1)
        XCTAssertEqual(data.sessions(inProgram: nil).count, 3)
        data.programs[0].name = "Renamed"
        XCTAssertEqual(data.title(for: recorded), "Starter - Upper")
        let csv = try HistoryCSV.decode(HistoryCSV.export(data))
        var target = TrainingData.starter()
        XCTAssertEqual(try target.importHistory(csv), 3)
        XCTAssertEqual(target.sessions(inProgram: program.id).count, 1)
        XCTAssertEqual(target.title(for: target.sessions.first { $0.id == recorded.id }!), "Starter - Upper")
        XCTAssertEqual(target.recordedPrograms.first { $0.id == program.id }?.name, "Starter")
        data.removeProgram(program.id)
        XCTAssertEqual(data.sessions(inProgram: program.id).count, 1)
        XCTAssertEqual(data.title(for: recorded), "Starter - Upper")
        let restored = try LocalRepository.decode(LocalRepository.encode(data))
        XCTAssertEqual(restored.recordedPrograms.first { $0.id == program.id }?.name, "Starter")
    }

    func testSubstitutionDoesNotBorrowAnUnrelatedTrackWithTheSameLabel() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0]
        let original = data.variant(day.slots.last!.variantID)!
        let target = data.exercises.first { $0.name == "Dumbbell lateral raise" }!
        let foreign = Variant(exerciseID: target.id, label: original.label, workingWeight: 80, notes: "Other day", sets: [SetPlan(reps: 3, repCeiling: nil)])
        data.variants.append(foreign)
        let otherDay = Routine(name: "Other", slots: [RoutineSlot(variantID: foreign.id)])
        data.routines.append(otherDay)
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises.last!
        try data.substitute(sessionExerciseID: item.id, with: target.id, future: true)
        let replacement = data.activeSession!.exercises.last!
        XCTAssertNotEqual(replacement.variantID, foreign.id)
        XCTAssertEqual(replacement.sets[0].weight, 0)
        try data.setWorkingWeight(10, for: replacement.id, saveFuture: true)
        XCTAssertEqual(data.variant(foreign.id), foreign)
        let storedID = replacement.variantID
        try data.substitute(sessionExerciseID: replacement.id, with: original.exerciseID, future: true)
        let returned = data.activeSession!.exercises.last!
        XCTAssertEqual(returned.variantID, original.id)
        try data.substitute(sessionExerciseID: returned.id, with: target.id, future: false)
        XCTAssertEqual(data.activeSession!.exercises.last!.variantID, storedID)
        XCTAssertEqual(data.activeSession!.exercises.last!.workingWeight, 10)
        XCTAssertEqual(data.routine(otherDay.id), otherDay)
        XCTAssertNoThrow(try data.validated())
    }

    func testIncrementalHistoryImportsKeepOneTrackAcrossRenamesAndBackupReload() throws {
        var source = TrainingData.starter()
        var target = TrainingData.starter()
        let day = source.dayTemplates[0]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try source.start(routineID: day.id, now: start)
        var item = source.activeSession!.exercises[0]
        try source.toggleSet(exerciseID: item.id, setID: item.sets.first { $0.plan.kind == .working }!.id, now: start)
        try source.finish(now: start.addingTimeInterval(600))
        XCTAssertEqual(try target.importHistory(HistoryCSV.decode(HistoryCSV.export(source))), 1)
        let first = target.sessions[0].exercises[0]
        target = try LocalRepository.decode(LocalRepository.encode(target))
        let e = source.exercises.firstIndex { $0.id == item.exerciseID }!
        source.exercises[e].name = "Renamed press"
        try source.start(routineID: day.id, now: start.addingTimeInterval(86400))
        item = source.activeSession!.exercises[0]
        try source.toggleSet(exerciseID: item.id, setID: item.sets.first { $0.plan.kind == .working }!.id, now: start.addingTimeInterval(86400))
        try source.finish(now: start.addingTimeInterval(87000))
        // Import just the new workout, without overlapping rows to infer from.
        var delta = source; delta.sessions = [source.sessions[1]]
        XCTAssertEqual(try target.importHistory(HistoryCSV.decode(HistoryCSV.export(delta))), 1)
        let second = target.sessions[1].exercises[0]
        XCTAssertEqual(second.variantID, first.variantID)
        XCTAssertEqual(second.exerciseID, first.exerciseID)
        XCTAssertEqual(second.name, "Renamed press")
        XCTAssertEqual(target.points(exerciseID: first.exerciseID, variantID: first.variantID, metric: .weight).count, 2)
        XCTAssertEqual(try target.importHistory(HistoryCSV.decode(HistoryCSV.export(source))), 0)
        XCTAssertNoThrow(try target.validated())
    }

    func testLiveAddedExerciseUsesItsDayTrackRatherThanMatchingLabels() throws {
        var data = TrainingData.starter()
        let upper = data.dayTemplates[0], lower = data.dayTemplates[1]
        let exercise = data.exercises.first { $0.name == "Dumbbell curl" }!
        let foreign = Variant(exerciseID: exercise.id, label: upper.name, workingWeight: 90)
        data.variants.append(foreign)
        try data.start(routineID: upper.id)
        try data.addExerciseToSession(exercise.id)
        let added = data.activeSession!.exercises.last!
        XCTAssertNotEqual(added.variantID, foreign.id)
        try data.setWorkingWeight(12, for: added.id, saveFuture: true)
        try data.toggleSet(exerciseID: added.id, setID: added.sets[0].id)
        try data.finish()
        try data.start(routineID: lower.id)
        try data.addExerciseToSession(exercise.id)
        let other = data.activeSession!.exercises.last!
        XCTAssertNotEqual(other.variantID, added.variantID)
        XCTAssertEqual(other.workingWeight, 0)
        data.activeSession = nil
        try data.start(routineID: upper.id)
        data.activeSession!.name = "Renamed session"
        try data.addExerciseToSession(exercise.id)
        XCTAssertEqual(data.activeSession!.exercises.last!.variantID, added.variantID)
        XCTAssertEqual(data.activeSession!.exercises.last!.workingWeight, 12)
        data.activeSession = Session(name: upper.name)
        try data.addExerciseToSession(exercise.id)
        XCTAssertNotEqual(data.activeSession!.exercises.last!.variantID, added.variantID)
        XCTAssertNotEqual(data.activeSession!.exercises.last!.variantID, foreign.id)
        XCTAssertEqual(data.variant(foreign.id), foreign)
        XCTAssertNoThrow(try data.validated())
    }

    func testLiveAddedExerciseUsesLatestDatedTrackWhenHistoryIsUnsorted() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0]
        let exercise = data.exercises.first { $0.name == "Dumbbell curl" }!
        let older = Variant(exerciseID: exercise.id, label: "Older", workingWeight: 9)
        let newer = Variant(exerciseID: exercise.id, label: "Newer", workingWeight: 17)
        data.variants += [older, newer]
        func historical(_ variant: Variant, at time: Double) -> Session {
            let date = Date(timeIntervalSince1970: time)
            var item = SessionExercise(variant: variant, exercise: exercise)
            item.sets[0].completedAt = date
            return Session(routineID: day.id, name: day.name, startedAt: date, endedAt: date.addingTimeInterval(60), exercises: [item])
        }
        data.sessions = [historical(newer, at: 200), historical(older, at: 100)]
        try data.start(routineID: day.id)
        try data.addExerciseToSession(exercise.id)
        XCTAssertEqual(data.activeSession!.exercises.last!.variantID, newer.id)
        XCTAssertEqual(data.activeSession!.exercises.last!.workingWeight, 17)
        XCTAssertEqual(data.variant(older.id), older)
        XCTAssertNoThrow(try data.validated())
    }

    func testCopiedSubstitutedDayStartsAnIndependentSubstitutionFamily() throws {
        var data = TrainingData.starter()
        let day = data.dayTemplates[0]
        let original = data.variant(day.slots.last!.variantID)!
        let target = data.exercises.first { $0.name == "Dumbbell lateral raise" }!
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises.last!
        data.activeSession!.exercises[data.activeSession!.exercises.count - 1].notes = "Shoulder note before swapping"
        try data.substitute(sessionExerciseID: item.id, with: target.id, future: true)
        XCTAssertEqual(data.activeSession!.exercises.last!.notes, "Shoulder note before swapping")
        let replacementID = data.activeSession!.exercises.last!.variantID
        let copyID = try data.saveDayAsTemplate(day.id, name: "Copied day")
        data.activeSession = nil
        try data.start(routineID: copyID)
        let copied = data.activeSession!.exercises.last!
        XCTAssertNotEqual(copied.variantID, replacementID)
        try data.substitute(sessionExerciseID: copied.id, with: original.exerciseID, future: true)
        XCTAssertNotEqual(data.activeSession!.exercises.last!.variantID, original.id)
        XCTAssertEqual(data.routine(day.id)!.slots.last!.variantID, replacementID)
        XCTAssertNoThrow(try data.validated())
    }

    func testLegacyHistoryImportRecoversTrackIdentityFromOverlappingSessions() throws {
        var source = TrainingData.starter()
        let dayID = source.dayTemplates[0].id
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var target = TrainingData.starter()
        var firstID: UUID?
        for index in 0..<2 {
            let now = start.addingTimeInterval(Double(index) * 86400)
            try source.start(routineID: dayID, now: now)
            let item = source.activeSession!.exercises[0]
            try source.toggleSet(exerciseID: item.id, setID: item.sets.first { $0.plan.kind == .working }!.id, now: now)
            try source.finish(now: now.addingTimeInterval(600))
            XCTAssertEqual(try target.importHistory(HistoryCSV.decode(HistoryCSV.export(source))), 1)
            if index == 0 { firstID = target.sessions[0].exercises[0].variantID; target.historyImports = [] }
        }
        XCTAssertEqual(target.sessions[1].exercises[0].variantID, firstID)
        XCTAssertEqual(target.historyImports.count, 1)
        let before = target
        var broken = target
        broken.historyImports[0].variantID = UUID()
        XCTAssertThrowsError(try broken.validated())
        XCTAssertEqual(target, before)
    }

    func testHistoryCSVTransfersSnapshotsAndNotesWithoutChangingExistingPlans() throws {
        var source = TrainingData.starter()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try source.start(routineID: source.routines[0].id, now: start)
        source.activeSession!.notes = "Workout \"note\", =literal"
        source.activeSession!.exercises[0].notes = "=1+1\nSeat 4"
        source.activeSession!.exercises[0].recurringNotes = "Recurring note"
        let exercise = source.activeSession!.exercises[0]
        try source.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id, now: start.addingTimeInterval(30))
        try source.finish(now: start.addingTimeInterval(1200))
        let original = source.sessions[0]
        let bundle = try HistoryCSV.decode(HistoryCSV.export(source))
        let log = bundle.content.sessions[0]
        XCTAssertEqual(log.id, original.id)
        XCTAssertEqual(log.startedAt, original.startedAt)
        XCTAssertEqual(log.endedAt, original.endedAt)
        XCTAssertEqual(log.notes, original.notes)
        XCTAssertEqual(log.exercises[0].notes, original.exercises[0].notes)
        XCTAssertEqual(log.exercises[0].recurringNotes, original.exercises[0].recurringNotes)
        XCTAssertEqual(log.exercises[0].sets[0].weight, original.exercises[0].sets[0].weight)
        XCTAssertEqual(log.exercises[0].sets[0].completedAt, original.exercises[0].sets[0].completedAt)
        let plans = source.variants
        XCTAssertEqual(try source.importHistory(bundle), 0)
        XCTAssertEqual(source.variants, plans)
        var target = TrainingData.starter()
        let before = target.variants
        XCTAssertEqual(try target.importHistory(bundle), 1)
        XCTAssertEqual(try target.importHistory(bundle), 0)
        XCTAssertEqual(Array(target.variants.prefix(before.count)), before)
        XCTAssertNoThrow(try target.validated())
    }

    func testHistoryCSVKeepsRenamedExerciseSnapshotsAndLegacyImportIsStable() throws {
        var source = TrainingData.starter()
        let dayID = source.routines[0].id
        for index in 0..<2 {
            try source.start(routineID: dayID, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(index * 86400)))
            let item = source.activeSession!.exercises[0]
            if index == 1 { source.activeSession!.exercises[0].name = "Renamed movement"; source.activeSession!.exercises[0].label = "Renamed track" }
            try source.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
            try source.finish()
        }
        let bundle = try HistoryCSV.decode(HistoryCSV.export(source))
        XCTAssertEqual(bundle.content.sessions[1].exercises[0].name, "Renamed movement")
        XCTAssertEqual(bundle.content.sessions[1].exercises[0].label, "Renamed track")
        let csv = Data("date,workout,exercise,variant,weight_kg,reps,seconds,meters,rpe,notes\n2026-10-18T12:00:00Z,Upper,Press,Heavy,50,5,,,8,Test".utf8)
        let legacy = try HistoryCSV.decode(csv)
        XCTAssertEqual(legacy.warnings.count, 1)
        var target = TrainingData.starter()
        XCTAssertEqual(try target.importHistory(legacy), 1)
        XCTAssertEqual(try target.importHistory(HistoryCSV.decode(csv)), 0)
        XCTAssertNoThrow(try target.validated())
    }

    func testLongContextNamesAndClampedDropCountsStayValid() throws {
        var data = TrainingData.starter()
        let template = data.dayTemplates[0]
        let name = String(repeating: "A", count: 200)
        let id = try data.createProgram(name: name, templateIDs: [template.id])
        _ = try data.duplicateProgram(id)
        XCTAssertNoThrow(try data.validated())
        XCTAssertNil(SetTechniques.drops(workingWeight: 50, rounding: 1, count: 0).last!.restSeconds)
        XCTAssertNil(SetTechniques.drops(workingWeight: 50, rounding: 1, count: 100).last!.restSeconds)
    }

    func testProgramsCopyTemplatesAndKeepIndependentPositions() throws {
        var data = TrainingData.starter()
        let template = data.dayTemplates[0]
        let programID = try data.createProgram(name: "Custom", templateIDs: [template.id, data.dayTemplates[1].id])
        let otherID = try data.createProgram(name: "Other", templateIDs: [template.id])
        let first = data.routine(data.program(programID)!.dayIDs[0])!
        XCTAssertNotEqual(first.id, template.id)
        XCTAssertNotEqual(first.slots[0].variantID, template.slots[0].variantID)
        XCTAssertEqual(data.variant(first.slots[0].variantID)!.sets.map(\.kind), data.variant(template.slots[0].variantID)!.sets.map(\.kind))
        try data.loadProgram(programID)
        try data.start(routineID: first.id)
        let exercise = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        try data.loadProgram(otherID)
        try data.finish()
        XCTAssertEqual(data.program(programID)!.nextDayIndex, 1)
        XCTAssertEqual(data.program(otherID)!.nextDayIndex, 0)
        try data.loadProgram(programID)
        XCTAssertEqual(data.activeProgram!.nextDayIndex, 1)
        XCTAssertNoThrow(try data.validated())
    }

    func testOutOfOrderProgramDayDoesNotSkipRotation() throws {
        var data = TrainingData.starter()
        let p = data.activeProgram!
        try data.start(routineID: p.dayIDs[1])
        let exercise = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        try data.finish()
        XCTAssertEqual(data.program(p.id)!.nextDayIndex, 0)
        let reversed = Array(p.dayIDs.reversed())
        try data.reorderDays(reversed, in: p.id)
        XCTAssertEqual(data.program(p.id)!.nextDayID, p.dayIDs[0])
        data.removeDay(p.dayIDs[0])
        XCTAssertNoThrow(try data.validated())
    }

    func testProgramDeleteAndTemplateSavePreserveHistory() throws {
        var data = TrainingData.starter()
        let p = data.activeProgram!
        let dayID = p.dayIDs[0]
        let copy = try data.saveDayAsTemplate(dayID)
        XCTAssertTrue(data.dayTemplates.contains { $0.id == copy })
        try data.start(routineID: dayID)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id)
        data.removeProgram(p.id)
        try data.finish()
        XCTAssertEqual(data.sessions.count, 1)
        XCTAssertEqual(data.sessions[0].programID, p.id)
        XCTAssertNoThrow(try data.validated())
    }

    func testRoutineCSVRoundTripPreservesTechniquesAndAddsIndependentCopies() throws {
        var data = TrainingData.starter()
        let p = data.activeProgram!
        let vID = data.routine(p.dayIDs[0])!.slots[0].variantID
        let v = data.variants.firstIndex { $0.id == vID }!
        data.variants[v].notes = "=1+1\nSeat \"4\", right side"
        data.variants[v].sets += SetTechniques.myo(miniReps: 4, miniSets: 3, rest: 15)
        data.variants[v].sets += SetTechniques.drops(workingWeight: 100, rounding: 1, count: 2)
        let csv = try RoutineCSV.export(data, programID: p.id)
        let imported = try RoutineCSV.decode(csv)
        XCTAssertEqual(imported.content.programs.count, 1)
        XCTAssertEqual(imported.dayCount, 3)
        let originalVariant = data.variant(vID)!
        let transferredVariant = imported.content.variant(vID)!
        XCTAssertEqual(transferredVariant.sets, originalVariant.sets)
        XCTAssertEqual(transferredVariant.notes, originalVariant.notes)
        let before = data.sessions
        let ids = try data.importRoutines(imported, loadFirst: true)
        XCTAssertEqual(data.sessions, before)
        XCTAssertEqual(data.activeProgramID, ids.first)
        XCTAssertNotEqual(ids.first, p.id)
        let day = data.routine(data.program(ids[0])!.dayIDs[0])!
        XCTAssertNotEqual(day.slots[0].variantID, vID)
        XCTAssertEqual(data.variant(day.slots[0].variantID)!.sets.map(\.kind), originalVariant.sets.map(\.kind))
        XCTAssertNoThrow(try data.validated())
    }

    func testCSVHandlesQuotesNewlinesBOMSemicolonsAndSimpleDays() throws {
        let rows = [["day", "exercise", "reps_min", "working_weight_kg", "exercise_notes"], ["Upper", "Cable raise", "12", "5.5", "'literal\n\"quoted\", note"], ["Upper", "Cable raise", "15", "5.5", "'literal\n\"quoted\", note"]]
        let bytes = CSVCodec.render(rows)
        let parsed = try CSVCodec.parse(bytes)
        XCTAssertEqual(CSVCodec.unprotect(parsed[1][4]), rows[1][4])
        let bundle = try RoutineCSV.decode(bytes)
        XCTAssertEqual(bundle.dayCount, 1)
        XCTAssertEqual(bundle.setCount, 2)
        let alternate = Data("\u{FEFF}day;exercise;reps_min;working_weight_kg\r\nLower;Squat;5;20".utf8)
        XCTAssertEqual(try RoutineCSV.decode(alternate).setCount, 1)
        XCTAssertThrowsError(try CSVCodec.parse(Data("day,exercise\nUpper,\"bad".utf8)))
        XCTAssertThrowsError(try CSVCodec.parse(Data("day,exercise\nUpper,Squat,extra".utf8)))
        XCTAssertThrowsError(try RoutineCSV.decode(Data("day,exercise,rpe\nUpper,Press,11".utf8)))
    }

    func testCSVPreservesEmptyProgramsAndDaysAndRejectsInvalidReferences() throws {
        var data = TrainingData.starter()
        let id = try data.createProgram(name: "Blank")
        XCTAssertEqual(try RoutineCSV.decode(RoutineCSV.export(data, programID: id)).content.programs[0].dayIDs.count, 0)
        let dayID = try data.addDay(to: id, name: "Recovery")
        let bundle = try RoutineCSV.decode(RoutineCSV.export(data, programID: id))
        XCTAssertEqual(bundle.dayCount, 1)
        XCTAssertEqual(bundle.content.routine(dayID)!.slots.count, 0)
        var bad = bundle
        bad.content.programs[0].dayIDs = [UUID()]
        let before = data
        XCTAssertThrowsError(try data.importRoutines(bad))
        XCTAssertEqual(data, before)
    }

    func testCompletedExerciseStaysOpenByDefaultAndManualFocusPreservesResults() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises[0]
        for set in item.sets { try data.toggleSet(exerciseID: item.id, setID: set.id) }
        let completed = data.activeSession!.exercises[0].sets
        XCTAssertNil(data.collapseCompletedExercise(item.id))
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, false)
        let next = data.activeSession!.exercises[1]
        data.setExerciseExpanded(next.id, expanded: true, focus: true)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, true)
        data.setExerciseExpanded(item.id, expanded: true, focus: true)
        XCTAssertEqual(data.activeSession!.exercises[0].sets, completed)
        XCTAssertEqual(data.activeSession!.exercises[1].collapsed, true)
        let restored = try LocalRepository.decode(LocalRepository.encode(data))
        XCTAssertEqual(restored.activeSession!.completedSets, item.sets.count)
        XCTAssertEqual(restored.activeSession!.exercises[0].collapsed, false)
        XCTAssertEqual(restored.activeSession!.exercises[1].collapsed, true)
        XCTAssertEqual(restored.activeSession!.exercises[0].sets.map(\.weight), completed.map(\.weight))
        XCTAssertEqual(restored.activeSession!.exercises[0].sets.map(\.reps), completed.map(\.reps))
    }

    func testCollapseFocusAndManualExpansionDoNotChangeLoggedSets() throws {
        var data = TrainingData.starter()
        data.settings.autoCollapseCompleted = true
        try data.start(routineID: data.routines[0].id)
        let items = data.activeSession!.exercises
        XCTAssertEqual(items[0].collapsed, false)
        XCTAssertEqual(items[1].collapsed, true)
        data.setExerciseExpanded(items[1].id, expanded: true, focus: true)
        XCTAssertEqual(data.activeSession!.exercises[0].collapsed, true)
        for set in items[1].sets { try data.toggleSet(exerciseID: items[1].id, setID: set.id) }
        let next = data.collapseCompletedExercise(items[1].id)
        XCTAssertEqual(next, items[2].id)
        XCTAssertEqual(data.activeSession!.exercises[1].collapsed, true)
        data.setExerciseExpanded(items[1].id, expanded: true)
        XCTAssertNil(data.collapseCompletedExercise(items[1].id))
        XCTAssertEqual(data.activeSession!.exercises[1].collapsed, false)
        XCTAssertEqual(data.activeSession!.completedSets, items[1].sets.count)
    }

    func testLiveWarmupUsesTodayWeightAndSetFormulaEditing() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        let item = data.activeSession!.exercises[0]
        try data.setWorkingWeight(100, for: item.id, saveFuture: false)
        try data.addSessionSet(to: item.id, warmup: true)
        let added = data.activeSession!.exercises[0].sets.last!
        let increment = data.variant(item.variantID)!.rounding
        XCTAssertEqual(added.weight!, floor(50 / increment) * increment, accuracy: 0.00001)
        var plan = added.plan; plan.percent = 75; plan.rpe = 5; plan.reps = nil
        try data.replaceSetPlan(exerciseID: item.id, setID: added.id, plan: plan)
        let updated = data.activeSession!.exercises[0].sets.last!
        XCTAssertEqual(updated.weight!, floor(75 / increment) * increment, accuracy: 0.00001)
        XCTAssertNil(updated.reps); XCTAssertEqual(updated.rpe, 5)
    }

    func testLegacyBackupLoadsWithoutNewProgramAndSessionFields() throws {
        var data = TrainingData.starter()
        try data.start(routineID: data.routines[0].id)
        var json = try JSONSerialization.jsonObject(with: LocalRepository.encode(data)) as! [String: Any]
        json.removeValue(forKey: "programs"); json.removeValue(forKey: "activeProgramID"); json.removeValue(forKey: "historyImports")
        var session = json["activeSession"] as! [String: Any]
        session.removeValue(forKey: "programID"); session.removeValue(forKey: "advancesProgram")
        var exercises = session["exercises"] as! [[String: Any]]
        for i in exercises.indices { for key in ["workingWeight", "roundingIncrement", "collapsed", "keepExpanded"] { exercises[i].removeValue(forKey: key) } }
        session["exercises"] = exercises; json["activeSession"] = session
        let loaded = try LocalRepository.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(loaded.programs.isEmpty)
        XCTAssertEqual(loaded.activeSession!.exercises[0].workingLoad(fallback: 0), itemWeight(data))
    }
    private func itemWeight(_ data: TrainingData) -> Double { data.activeSession!.exercises[0].sets.first { $0.plan.load == .working }!.weight! }
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
        for set in exercise.sets {
            let e = data.activeSession!.exercises.count - 1
            let index = data.activeSession!.exercises[e].sets.firstIndex { $0.id == set.id }!
            data.activeSession!.exercises[e].sets[index].reps = 15
            try data.toggleSet(exerciseID: exercise.id, setID: set.id)
        }
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
        let variantID = data.sessions.flatMap(\.exercises).first { $0.exerciseID == exercise.id }!.variantID
        XCTAssertEqual(data.points(exerciseID: exercise.id, metric: .weight).count, 20)
        XCTAssertEqual(data.points(exerciseID: exercise.id, variantID: variantID, metric: .weight).count, 10)
        XCTAssertEqual(data.sessions(inProgram: data.activeProgramID).count, 30)
        let bytes = try LocalRepository.encode(data)
        XCTAssertEqual(try LocalRepository.decode(bytes).sessions.count, 30)
    }

    func testColorThemeOverridesDefaultsPerAppearanceAndValidates() throws {
        var theme = ColorTheme()
        XCTAssertEqual(theme.hex(.action, dark: false), ColorRole.action.defaultHex(dark: false))
        theme.set(.warmup, dark: true, hex: 0x123456)
        XCTAssertEqual(theme.hex(.warmup, dark: true), 0x123456)
        XCTAssertEqual(theme.hex(.warmup, dark: false), ColorRole.warmup.defaultHex(dark: false))
        XCTAssertTrue(theme.isCustomized(.warmup, dark: true))
        theme.set(.warmup, dark: true, hex: ColorRole.warmup.defaultHex(dark: true))
        XCTAssertFalse(theme.isCustomized(.warmup, dark: true))
        XCTAssertEqual(ColorTheme.parse("#0A84FF"), 0x0A84FF)
        XCTAssertNil(ColorTheme.parse("#12345"))
        var data = TrainingData.starter()
        data.settings.colors = theme
        XCTAssertNoThrow(try data.validated())
        let decoded = try LocalRepository.decode(LocalRepository.encode(data))
        XCTAssertEqual(decoded.settings.colors, theme)
        data.settings.colors?.light["action"] = "blue"
        XCTAssertThrowsError(try data.validated())
        data.settings.colors?.light = ["unknown": "#FFFFFF"]
        XCTAssertThrowsError(try data.validated())
        let partial = try JSONDecoder().decode(ColorTheme.self, from: Data(##"{"dark":{"action":"#112233","future":"#FFFFFF","rest":"teal"}}"##.utf8))
        XCTAssertEqual(partial.dark, ["action": "#112233"])
        XCTAssertTrue(partial.light.isEmpty)
    }

    func testCustomSetTypesCountAsTheirBaseKindAndTravelThroughCSVAndSync() throws {
        var data = TrainingData.starter()
        let backoff = CustomSetType(name: "Back-off", badge: "b", countsAs: .working)
        try data.saveSetType(backoff)
        XCTAssertEqual(data.customSetTypes[0].badge, "B")
        XCTAssertThrowsError(try data.saveSetType(CustomSetType(name: "back-off", badge: "X")))
        XCTAssertThrowsError(try data.saveSetType(CustomSetType(name: "Warm-up", badge: "X")))
        let day = data.dayTemplates[0], v = data.variants.firstIndex { $0.id == day.slots[0].variantID }!
        var plan = data.variants[v].sets.last { $0.kind == .working }!
        plan.id = UUID(); plan.customTypeID = backoff.id; data.variants[v].sets.append(plan)
        XCTAssertEqual(data.setTypeTitle(plan), "Back-off")

        // Changing what a type counts as updates saved prescriptions.
        var feeder = data.customSetTypes[0]; feeder.countsAs = .warmup
        try data.saveSetType(feeder)
        XCTAssertEqual(data.variants[v].sets.last!.kind, .warmup)
        feeder.countsAs = .working; try data.saveSetType(feeder)

        // Day CSV keeps the type and matches it by name on import.
        let csv = try RoutineCSV.decode(RoutineCSV.export(data, dayID: day.id)).content
        XCTAssertEqual(csv.customSetTypes.map(\.name), ["Back-off"])
        var other = TrainingData(); try other.importRoutines(RoutineBundle(content: csv))
        let imported = other.variants.flatMap(\.sets).first { $0.customTypeID != nil }!
        XCTAssertEqual(other.setTypeTitle(imported), "Back-off"); XCTAssertEqual(imported.kind, .working)
        try other.importRoutines(RoutineBundle(content: csv))
        XCTAssertEqual(other.customSetTypes.count, 1)

        // Live add copies the last work set and counts toward volume.
        try data.start(routineID: day.id)
        let item = data.activeSession!.exercises[0]
        try data.addTypedSet(to: item.id, kind: .working, customTypeID: backoff.id)
        let added = data.activeSession!.exercises[0].sets.last!
        XCTAssertEqual(added.plan.customTypeID, backoff.id); XCTAssertEqual(added.plan.kind, .working); XCTAssertNil(added.completedAt)
        try data.toggleSet(exerciseID: item.id, setID: added.id)
        XCTAssertGreaterThan(data.activeSession!.volume, 0)
        try data.addTypedSet(to: item.id, kind: .warmup)
        XCTAssertEqual(data.activeSession!.exercises[0].sets.last!.plan.kind, .warmup)
        try data.finish()

        // History CSV keeps the type name; sync carries the type record.
        let history = try HistoryCSV.decode(HistoryCSV.export(data)).content
        XCTAssertTrue(history.customSetTypes.contains { $0.name == "Back-off" })
        var state = DeviceSyncState(); try state.capture(data)
        var receiver = DeviceSyncState(); let synced = try receiver.merge([state], into: TrainingData())
        XCTAssertEqual(synced.customSetTypes, data.customSetTypes)

        // Removing a type leaves sets counting as before, under the built-in name.
        data.removeSetType(backoff.id)
        XCTAssertNil(data.variants[v].sets.last!.customTypeID)
        XCTAssertEqual(data.variants[v].sets.last!.kind, .working)
        XCTAssertNoThrow(try data.validated())
        let legacy = try LocalRepository.decode(LocalRepository.encode(TrainingData.starter()))
        XCTAssertTrue(legacy.customSetTypes.isEmpty)
    }

    func testSkipRecordsUncheckedDayAndAdvancesProgram() throws {
        var data = TrainingData.starter()
        try data.createProgram(name: "Test", templateIDs: data.dayTemplates.map(\.id))
        let program = data.programs.last!
        let first = program.dayIDs[0], second = program.dayIDs[1]
        try data.skipNextDay(in: program.id)
        XCTAssertEqual(data.program(program.id)!.nextDayID, second)
        let skipped = data.sessions.last!
        XCTAssertEqual(skipped.skipped, true); XCTAssertEqual(skipped.routineID, first)
        XCTAssertEqual(skipped.completedSets, 0); XCTAssertGreaterThan(skipped.totalSets, 0)
        XCTAssertTrue(data.muscleSummary().isEmpty)
        XCTAssertNoThrow(try data.validated())
        let decoded = try LocalRepository.decode(LocalRepository.encode(data))
        XCTAssertEqual(decoded.sessions.last!.skipped, true)
        try data.start(routineID: second)
        XCTAssertThrowsError(try data.skipNextDay(in: program.id))
        let templates = data.dayTemplates.map(\.id)
        try data.reorderTemplates(templates.reversed())
        XCTAssertEqual(data.dayTemplates.map(\.id), templates.reversed())
        XCTAssertThrowsError(try data.reorderTemplates([templates[0]]))
    }

    func testMovingUpcomingDaysChangesWhatComesNext() throws {
        var data = TrainingData()
        let id = try data.createProgram(name: "Four", templateIDs: [])
        for name in ["A", "B", "C", "D"] { _ = try data.addDay(to: id, name: name) }
        let names = { data.upcomingDays(id).compactMap { data.routine($0)?.name } }
        let day = { (name: String) in data.routines.first { $0.name == name }!.id }
        try data.selectNextDay(day("B"), in: id)
        XCTAssertEqual(names(), ["B", "C", "D", "A"])
        try data.moveUpcomingDay(day("B"), by: 1, in: id)
        XCTAssertEqual(names(), ["C", "B", "D", "A"])
        XCTAssertEqual(data.program(id)!.nextDayID, day("C"))
        try data.moveUpcomingDay(day("A"), by: -1, in: id)
        XCTAssertEqual(names(), ["C", "B", "A", "D"])
        XCTAssertThrowsError(try data.moveUpcomingDay(day("C"), by: -1, in: id))
        XCTAssertThrowsError(try data.moveUpcomingDay(day("D"), by: 1, in: id))
        XCTAssertNoThrow(try data.validated())
    }

    func testShowcaseIsValidHistoryWithPushNext() throws {
        let data = TrainingData.showcase(now: Date(timeIntervalSince1970: 1_792_300_000))
        XCTAssertNoThrow(try data.validated())
        XCTAssertEqual(data.activeProgram?.name, "Push Pull Legs")
        XCTAssertEqual(data.activeProgram?.nextDayID.flatMap(data.routine)?.name, "Push")
        XCTAssertGreaterThan(data.sessions.count, 60)
        XCTAssertEqual(data.sessions.filter { $0.skipped == true }.count, 1)
        XCTAssertEqual(data.programs.count, 2); XCTAssertEqual(data.dayTemplates.map(\.name), ["Arms", "Conditioning"])
        XCTAssertTrue(data.sessions.flatMap(\.exercises).flatMap(\.sets).contains { $0.plan.customTypeID != nil && $0.completedAt != nil })
        let bench = data.exercises.first { $0.name == "Bench press" }!
        XCTAssertGreaterThan(data.points(exerciseID: bench.id, metric: .weight).count, 15)
    }

    /// One finished strength session from 18:00 to 19:10 on a fixed day, with a logged set.
    private func healthLibrary() throws -> (TrainingData, UUID, Date) {
        var data = TrainingData.starter()
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        try data.start(routineID: data.dayTemplates[0].id, now: start)
        let first = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: first.id, setID: first.sets[0].id, now: start.addingTimeInterval(120))
        try data.finish(now: start.addingTimeInterval(70 * 60))
        return (data, data.sessions.last!.id, start)
    }

    func testHealthAddsWatchCaloriesAndNeverSavesOverAWatchWorkout() throws {
        var (data, id, start) = try healthLibrary()
        data.settings.health = HealthSettings(read: true, write: true, writeSince: start.addingTimeInterval(-86_400))
        let watch = HealthWorkout(start: start.addingTimeInterval(-120), end: start.addingTimeInterval(72 * 60), sourceName: "Apple Watch", activityName: "Strength training", activeKcal: 412, averageHeartRate: 128)
        let walk = HealthWorkout(start: start.addingTimeInterval(-3 * 3600), end: start.addingTimeInterval(-2.5 * 3600), sourceName: "Apple Watch", activeKcal: 90)
        let plan = data.reconcileHealth([watch, walk], now: start.addingTimeInterval(3 * 3600))
        XCTAssertEqual(plan, HealthPlan())
        let link = try XCTUnwrap(data.sessions.last!.health)
        XCTAssertEqual(link.workoutIDs, [watch.id]); XCTAssertEqual(link.sourceName, "Apple Watch")
        XCTAssertEqual(link.activeKcal ?? 0, 412, accuracy: 0.001); XCTAssertEqual(link.averageHeartRate ?? 0, 128, accuracy: 0.001)
        XCTAssertNoThrow(try data.validated())
        // Values stay in Lifting's log when Health stops sharing them, for example after access is turned off.
        _ = data.reconcileHealth([], now: start.addingTimeInterval(4 * 3600))
        XCTAssertEqual(data.sessions.last!.health?.activeKcal ?? 0, 412, accuracy: 0.001)
        // A cardio warm-up and the strength workout recorded separately both count.
        var (two, _, twoStart) = try healthLibrary()
        let bike = HealthWorkout(start: twoStart.addingTimeInterval(-5 * 60), end: twoStart.addingTimeInterval(10 * 60), sourceName: "Apple Watch", activeKcal: 100, averageHeartRate: 140)
        let lift = HealthWorkout(start: twoStart.addingTimeInterval(10 * 60), end: twoStart.addingTimeInterval(70 * 60), sourceName: "Apple Watch", activeKcal: 300, averageHeartRate: 120)
        _ = two.reconcileHealth([bike, lift], now: twoStart.addingTimeInterval(3 * 3600))
        XCTAssertEqual(two.sessions.last!.health?.activeKcal ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(two.sessions.last!.health?.averageHeartRate ?? 0, 124, accuracy: 0.001)
        XCTAssertEqual(two.sessions.last!.health?.workoutIDs.count, 2)
        _ = id
    }

    func testHealthSavesOnlyWhenNothingElseRecordedAndRemovesItsCopyWhenTheWatchArrives() throws {
        var (data, id, start) = try healthLibrary()
        let end = start.addingTimeInterval(70 * 60)
        // Off by default, and never for sessions that ended before saving was turned on.
        XCTAssertEqual(data.reconcileHealth([], now: end.addingTimeInterval(3600)), HealthPlan())
        data.settings.health = HealthSettings(read: true, write: true, writeSince: end.addingTimeInterval(60))
        XCTAssertEqual(data.reconcileHealth([], now: end.addingTimeInterval(3600)), HealthPlan())
        data.settings.health?.writeSince = start
        // Waits for a watch workout to reach the phone before saving.
        XCTAssertEqual(data.reconcileHealth([], now: end.addingTimeInterval(5 * 60)), HealthPlan())
        XCTAssertEqual(data.reconcileHealth([], now: end.addingTimeInterval(11 * 60)), HealthPlan(saves: [HealthSave(sessionID: id, start: start, end: end, activity: .strength)]))
        let copy = HealthWorkout(start: start, end: end, sourceName: "Lifting", isOwn: true, sessionID: id, activityName: "Strength training")
        data.recordSavedHealthWorkout(copy.id, for: id)
        XCTAssertEqual(data.sessions.last!.health?.savedWorkoutIDs, [copy.id])
        // Already saved: nothing to do.
        XCTAssertEqual(data.reconcileHealth([copy], now: end.addingTimeInterval(20 * 60)), HealthPlan())
        // The watch workout shows up later: Lifting removes only its own copy and takes the watch's calories.
        let watch = HealthWorkout(start: start.addingTimeInterval(60), end: end.addingTimeInterval(60), sourceName: "Apple Watch", activeKcal: 380, averageHeartRate: 131)
        let plan = data.reconcileHealth([copy, watch], now: end.addingTimeInterval(30 * 60))
        XCTAssertEqual(plan, HealthPlan(deletions: [copy.id]))
        XCTAssertNil(data.sessions.last!.health?.savedWorkoutIDs)
        XCTAssertEqual(data.sessions.last!.health?.activeKcal ?? 0, 380, accuracy: 0.001)
        // Once the watch recorded the time, Lifting never saves it again.
        XCTAssertEqual(data.reconcileHealth([watch], now: end.addingTimeInterval(3600)), HealthPlan())
        XCTAssertEqual(data.reconcileHealth([], now: end.addingTimeInterval(7200)), HealthPlan())
    }

    func testHealthTreatsAnotherAppsEmptyWorkoutAsRecordedAndRespectsUnlinking() throws {
        var (data, id, start) = try healthLibrary()
        let end = start.addingTimeInterval(70 * 60)
        data.settings.health = HealthSettings(read: true, write: true, writeSince: start)
        // Another lifting app logged the time without calories: nothing to link, and nothing to save over it.
        let other = HealthWorkout(start: start.addingTimeInterval(30), end: end, sourceName: "Other App")
        XCTAssertEqual(data.reconcileHealth([other], now: end.addingTimeInterval(3600)), HealthPlan())
        XCTAssertNil(data.sessions.last!.health)
        // Unlinking a wrong match keeps the session unlinked until asked again.
        let watch = HealthWorkout(start: start, end: end, sourceName: "Apple Watch", activeKcal: 250)
        _ = data.reconcileHealth([watch], now: end.addingTimeInterval(3600))
        XCTAssertNotNil(data.sessions.last!.health?.activeKcal)
        data.unlinkHealth(id)
        _ = data.reconcileHealth([watch], now: end.addingTimeInterval(7200))
        XCTAssertNil(data.sessions.last!.health?.activeKcal); XCTAssertEqual(data.sessions.last!.health?.unlinked, true)
        data.relinkHealth(id)
        _ = data.reconcileHealth([watch], now: end.addingTimeInterval(7300))
        XCTAssertEqual(data.sessions.last!.health?.activeKcal ?? 0, 250, accuracy: 0.001)
        // Skipped days and old sessions are left alone.
        try data.createProgram(name: "Skip test", templateIDs: [data.dayTemplates[0].id])
        try data.loadProgram(data.programs.last!.id)
        try data.skipNextDay(in: data.programs.last!.id, now: start.addingTimeInterval(86_400))
        let skippedStart = start.addingTimeInterval(86_400)
        _ = data.reconcileHealth([HealthWorkout(start: skippedStart, end: skippedStart.addingTimeInterval(3600), sourceName: "Apple Watch", activeKcal: 99)], now: skippedStart.addingTimeInterval(7200))
        XCTAssertNil(data.sessions.last!.health)
        XCTAssertNil(data.healthRange(now: start.addingTimeInterval(HealthMatching.lookback + 86_400 * 3)))
        // Invalid values are rejected.
        var bad = data; bad.sessions[0].health = HealthLink(activeKcal: -1)
        XCTAssertThrowsError(try bad.validated())
    }

    func testHealthValuesStayOutOfSharedFoldersButTravelInHistoryCSV() throws {
        var (data, id, start) = try healthLibrary()
        _ = data.reconcileHealth([HealthWorkout(start: start, end: start.addingTimeInterval(70 * 60), sourceName: "Apple Watch", activeKcal: 333, averageHeartRate: 125)], now: start.addingTimeInterval(3 * 3600))
        var state = DeviceSyncState()
        try state.capture(data)
        let payloads = state.records.values.compactMap(\.payload).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertFalse(payloads.contains { $0.contains("activeKcal") })
        // Merging another device's copy keeps this device's health values.
        var other = DeviceSyncState(); other.clock = state.clock + 1
        var remote = data; remote.sessions[remote.sessions.count - 1].notes = "From the iPad"
        try other.capture(remote)
        let merged = try state.merge([other], into: data)
        XCTAssertEqual(merged.sessions.last!.notes, "From the iPad")
        XCTAssertEqual(merged.sessions.last!.health?.activeKcal ?? 0, 333, accuracy: 0.001)
        XCTAssertNil(data.withoutHealthData.sessions.last!.health)
        let bundle = try HistoryCSV.decode(HistoryCSV.export(data))
        let imported = try XCTUnwrap(bundle.content.sessions.first { $0.id == id }?.health)
        XCTAssertEqual(imported.activeKcal ?? 0, 333, accuracy: 0.001); XCTAssertEqual(imported.averageHeartRate ?? 0, 125, accuracy: 0.001)
        XCTAssertEqual(imported.sourceName, "Apple Watch")
    }

    func testHealthCountsEachWorkoutTowardOneSessionOnly() throws {
        var (data, first, start) = try healthLibrary()
        // A second session six minutes after the first one ended.
        let secondStart = start.addingTimeInterval(76 * 60)
        try data.start(routineID: data.dayTemplates[1].id, now: secondStart)
        let item = data.activeSession!.exercises[0]
        try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id, now: secondStart.addingTimeInterval(60))
        try data.finish(now: secondStart.addingTimeInterval(40 * 60))
        let second = data.sessions.last!.id
        let early = HealthWorkout(start: start.addingTimeInterval(65 * 60), end: start.addingTimeInterval(72 * 60), sourceName: "Apple Watch", activeKcal: 150)
        let late = HealthWorkout(start: secondStart.addingTimeInterval(-2 * 60), end: secondStart.addingTimeInterval(41 * 60), sourceName: "Apple Watch", activeKcal: 320, averageHeartRate: 132)
        // The early workout is within ten minutes of both sessions but counts only toward the one it overlaps.
        _ = data.reconcileHealth([early, late], now: secondStart.addingTimeInterval(3 * 3600))
        XCTAssertEqual(data.sessions.first { $0.id == first }!.health?.activeKcal ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(data.sessions.first { $0.id == second }!.health?.activeKcal ?? 0, 320, accuracy: 0.001)
        // A workout first linked to the earlier session moves when a closer session appears, without counting twice.
        var (moving, firstID, movingStart) = try healthLibrary()
        let gapWorkout = HealthWorkout(start: movingStart.addingTimeInterval(74 * 60), end: movingStart.addingTimeInterval(79 * 60), sourceName: "Apple Watch", activeKcal: 60)
        _ = moving.reconcileHealth([gapWorkout], now: movingStart.addingTimeInterval(80 * 60))
        XCTAssertEqual(moving.sessions.first { $0.id == firstID }!.health?.activeKcal ?? 0, 60, accuracy: 0.001)
        let laterStart = movingStart.addingTimeInterval(76 * 60)
        try moving.start(routineID: moving.dayTemplates[1].id, now: laterStart)
        let laterItem = moving.activeSession!.exercises[0]
        try moving.toggleSet(exerciseID: laterItem.id, setID: laterItem.sets[0].id, now: laterStart.addingTimeInterval(60))
        try moving.finish(now: laterStart.addingTimeInterval(30 * 60))
        _ = moving.reconcileHealth([gapWorkout], now: laterStart.addingTimeInterval(3 * 3600))
        XCTAssertNil(moving.sessions.first { $0.id == firstID }!.health?.activeKcal)
        XCTAssertEqual(moving.sessions.last!.health?.activeKcal ?? 0, 60, accuracy: 0.001)
    }

    /// Finishes a session from a day template, completing the first set of each listed exercise.
    private func finishSession(_ data: inout TrainingData, day: Int, at start: Date, minutes: Double, exercises: [Int] = [0]) throws -> UUID {
        try data.start(routineID: data.dayTemplates[day].id, now: start)
        for e in exercises {
            let item = data.activeSession!.exercises[e]
            try data.toggleSet(exerciseID: item.id, setID: item.sets[0].id, now: start.addingTimeInterval(minutes * 60 - 60))
        }
        try data.finish(now: start.addingTimeInterval(minutes * 60))
        return data.sessions.last!.id
    }

    func testHealthSplitsOneWatchWorkoutAcrossBackToBackSessions() throws {
        var data = TrainingData.starter()
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        data.settings.health = HealthSettings(read: true, write: true, writeSince: start)
        let lift = try finishSession(&data, day: 0, at: start, minutes: 40)
        let cardio = try finishSession(&data, day: 1, at: start.addingTimeInterval(40 * 60), minutes: 30, exercises: [2])
        // One watch workout ran through both: 5 kcal a minute while lifting, 10 while running.
        let segments = (0..<70).map { minute in
            HealthSegment(start: start.addingTimeInterval(Double(minute) * 60), end: start.addingTimeInterval(Double(minute + 1) * 60), kcal: minute < 40 ? 5 : 10)
        }
        let watch = HealthWorkout(start: start, end: start.addingTimeInterval(70 * 60), sourceName: "Apple Watch", activityName: "Strength training", activeKcal: 500, averageHeartRate: 130, energySegments: segments)
        let plan = data.reconcileHealth([watch], now: start.addingTimeInterval(3 * 3600))
        XCTAssertEqual(plan, HealthPlan())
        let first = try XCTUnwrap(data.sessions.first { $0.id == lift }?.health), second = try XCTUnwrap(data.sessions.first { $0.id == cardio }?.health)
        XCTAssertEqual(first.activeKcal ?? 0, 200, accuracy: 0.001); XCTAssertEqual(second.activeKcal ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(first.parts?.first?.duration ?? 0, 40 * 60, accuracy: 0.001); XCTAssertEqual(second.parts?.first?.duration ?? 0, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(first.averageHeartRate ?? 0, 130, accuracy: 0.001)
        // Without per-minute energy, calories are split by time.
        var timed = watch; timed.energySegments = nil
        _ = data.reconcileHealth([timed], now: start.addingTimeInterval(3 * 3600))
        XCTAssertEqual(data.sessions.first { $0.id == lift }!.health?.activeKcal ?? 0, 500 * 40 / 70, accuracy: 0.001)
        XCTAssertEqual(data.sessions.first { $0.id == cardio }!.health?.activeKcal ?? 0, 500 * 30 / 70, accuracy: 0.001)
    }

    func testHealthLiftAndRunRecordedSeparatelyCountAsOneSession() throws {
        var (data, id, start) = try healthLibrary()
        let lift = HealthWorkout(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(50 * 60), sourceName: "Apple Watch", activityName: "Strength training", activeKcal: 280, averageHeartRate: 118)
        let run = HealthWorkout(start: start.addingTimeInterval(52 * 60), end: start.addingTimeInterval(70 * 60), sourceName: "Apple Watch", activityName: "Run", activeKcal: 190, averageHeartRate: 150)
        _ = data.reconcileHealth([run, lift], now: start.addingTimeInterval(3 * 3600))
        let link = try XCTUnwrap(data.sessions.first { $0.id == id }?.health)
        XCTAssertEqual(link.activeKcal ?? 0, 470, accuracy: 0.001)
        XCTAssertEqual(link.parts?.map(\.activityName), ["Strength training", "Run"])
        XCTAssertEqual(link.workoutIDs, [lift.id, run.id])
    }

    func testHealthSavesOnlyTheTimeNoOtherSourceRecorded() throws {
        var (data, id, start) = try healthLibrary()
        let end = start.addingTimeInterval(70 * 60)
        data.settings.health = HealthSettings(read: true, write: true, writeSince: start)
        // The watch recorded only the run at the end; Lifting saves the lifting before it.
        let run = HealthWorkout(start: start.addingTimeInterval(50 * 60), end: end, sourceName: "Apple Watch", activityName: "Run", activeKcal: 200)
        XCTAssertEqual(data.reconcileHealth([run], now: end.addingTimeInterval(11 * 60)), HealthPlan(saves: [HealthSave(sessionID: id, start: start, end: start.addingTimeInterval(50 * 60), activity: .strength)]))
        // A full-length copy saved before the run arrived is replaced by the uncovered part.
        let full = HealthWorkout(start: start, end: end, sourceName: "Lifting", isOwn: true, sessionID: id)
        XCTAssertEqual(data.reconcileHealth([full, run], now: end.addingTimeInterval(20 * 60)), HealthPlan(deletions: [full.id], saves: [HealthSave(sessionID: id, start: start, end: start.addingTimeInterval(50 * 60), activity: .strength)]))
        let trimmed = HealthWorkout(start: start, end: start.addingTimeInterval(50 * 60), sourceName: "Lifting", isOwn: true, sessionID: id)
        XCTAssertEqual(data.reconcileHealth([trimmed, run], now: end.addingTimeInterval(30 * 60)), HealthPlan())
        XCTAssertEqual(data.sessions.last!.health?.savedWorkoutIDs, [trimmed.id])
        XCTAssertEqual(data.sessions.last!.health?.activeKcal ?? 0, 200, accuracy: 0.001)
        // With saving off, a copy that repeats another recording is still removed.
        data.settings.health?.write = false
        XCTAssertEqual(data.reconcileHealth([full, run], now: end.addingTimeInterval(40 * 60)), HealthPlan(deletions: [full.id]))
    }

    func testHealthSavesCardioSessionsAsTheirActivity() throws {
        var data = TrainingData.starter()
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        data.settings.health = HealthSettings(read: true, write: true, writeSince: start)
        let id = try finishSession(&data, day: 1, at: start, minutes: 21, exercises: [2])
        let plan = data.reconcileHealth([], now: start.addingTimeInterval(3600))
        XCTAssertEqual(plan.saves.map(\.activity), [.running]); XCTAssertEqual(plan.saves.first?.sessionID, id)
        XCTAssertEqual(HealthActivity.cardio(named: "Row"), .rowing); XCTAssertEqual(HealthActivity.cardio(named: "Stair climber"), .stairs)
        XCTAssertEqual(HealthActivity.cardio(named: "Bike"), .cycling); XCTAssertEqual(HealthActivity.cardio(named: "Jump rope"), .mixedCardio)
    }
}
