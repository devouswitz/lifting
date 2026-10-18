#if !STANDALONE_CHECKS
import XCTest
@testable import LiftingCore
#else
import Foundation
#endif

final class TrainingTests: XCTestCase {
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
