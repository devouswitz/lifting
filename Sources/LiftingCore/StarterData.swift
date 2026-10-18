import Foundation

public extension TrainingData {
    static func starter() -> TrainingData {
        var data = TrainingData()
        let catalog: [(String, String, String, ExerciseMode)] = [
            ("Bench press", "Chest", "Barbell", .strength), ("Incline dumbbell press", "Chest", "Dumbbell", .strength),
            ("Cable lateral raise", "Shoulders", "Cable", .strength), ("Dumbbell lateral raise", "Shoulders", "Dumbbell", .strength),
            ("Overhead press", "Shoulders", "Barbell", .strength), ("Seated dumbbell press", "Shoulders", "Dumbbell", .strength),
            ("Barbell row", "Back", "Barbell", .strength), ("Chest-supported row", "Back", "Dumbbell", .strength),
            ("Lat pulldown", "Back", "Cable", .strength), ("Seated cable row", "Back", "Cable", .strength),
            ("Pull-up", "Back", "Bodyweight", .bodyweight), ("Chin-up", "Back", "Bodyweight", .bodyweight),
            ("Squat", "Legs", "Barbell", .strength), ("Front squat", "Legs", "Barbell", .strength),
            ("Deadlift", "Legs", "Barbell", .strength), ("Romanian deadlift", "Legs", "Barbell", .strength),
            ("Leg press", "Legs", "Machine", .strength), ("Leg extension", "Legs", "Machine", .strength),
            ("Leg curl", "Legs", "Machine", .strength), ("Bulgarian split squat", "Legs", "Dumbbell", .strength),
            ("Calf raise", "Legs", "Machine", .strength), ("Hip thrust", "Glutes", "Barbell", .strength),
            ("Cable curl", "Arms", "Cable", .strength), ("Dumbbell curl", "Arms", "Dumbbell", .strength),
            ("Hammer curl", "Arms", "Dumbbell", .strength), ("Triceps pressdown", "Arms", "Cable", .strength),
            ("Overhead triceps extension", "Arms", "Cable", .strength), ("Face pull", "Shoulders", "Cable", .strength),
            ("Push-up", "Chest", "Bodyweight", .bodyweight), ("Dip", "Chest", "Bodyweight", .bodyweight),
            ("Plank", "Core", "Bodyweight", .bodyweight), ("Hanging leg raise", "Core", "Bodyweight", .bodyweight),
            ("Run", "Cardio", "", .cardio), ("Sprint", "Cardio", "", .cardio), ("Bike", "Cardio", "Bike", .cardio),
            ("Row", "Cardio", "Rower", .cardio), ("Walk", "Cardio", "", .cardio), ("Stair climber", "Cardio", "Machine", .cardio)
        ]
        data.exercises = catalog.map { Exercise(name: $0.0, muscle: $0.1, equipment: $0.2, mode: $0.3) }
        func add(_ name: String, day: String, pounds: Double, reps: Int, upper: Int, count: Int, warmup: Bool = false) -> RoutineSlot {
            let exercise = data.exercises.first { $0.name == name }!
            var plans = (0..<count).map { _ in SetPlan(load: exercise.mode == .strength ? .working : .none, reps: reps, repCeiling: upper) }
            if warmup { plans.insert(contentsOf: [SetPlan(kind: .warmup, load: .percent, percent: 50, reps: 5, repCeiling: nil), SetPlan(kind: .warmup, load: .percent, percent: 75, reps: 3, repCeiling: nil)], at: 0) }
            let variant = Variant(exerciseID: exercise.id, label: day, workingWeight: WeightUnit.lb.kilograms(pounds), restSeconds: name == "Squat" || name == "Bench press" ? 180 : 90, sets: plans)
            data.variants.append(variant)
            return RoutineSlot(variantID: variant.id)
        }
        let upper = Routine(name: "Upper", slots: [add("Bench press", day: "Upper", pounds: 95, reps: 5, upper: 5, count: 3, warmup: true), add("Barbell row", day: "Upper", pounds: 65, reps: 8, upper: 10, count: 3), add("Cable lateral raise", day: "Upper", pounds: 10, reps: 12, upper: 15, count: 3)])
        var lower = Routine(name: "Lower", slots: [add("Squat", day: "Lower", pounds: 95, reps: 5, upper: 5, count: 3, warmup: true), add("Romanian deadlift", day: "Lower", pounds: 65, reps: 8, upper: 10, count: 3)])
        let run = data.exercises.first { $0.name == "Run" }!
        let runVariant = Variant(exerciseID: run.id, label: "Lower", restSeconds: 0, sets: [SetPlan(load: .none, reps: nil, repCeiling: nil, seconds: 1200, rpe: 6)])
        data.variants.append(runVariant); lower.slots.append(RoutineSlot(variantID: runVariant.id))
        let push = Routine(name: "Push", slots: [add("Incline dumbbell press", day: "Push", pounds: 30, reps: 8, upper: 12, count: 3), add("Cable lateral raise", day: "Push", pounds: 15, reps: 8, upper: 10, count: 3), add("Triceps pressdown", day: "Push", pounds: 30, reps: 10, upper: 15, count: 3)])
        data.routines = [upper, lower, push]
        data.activeProgramID = try? data.createProgram(name: "Starter", templateIDs: [upper.id, lower.id, push.id])
        return data
    }

    static func demo(now: Date = Date()) -> TrainingData {
        var data = starter()
        let days = data.dayTemplates
        for week in 0..<10 {
            for (day, routine) in days.enumerated() {
                let date = now.addingTimeInterval(Double(-70 + week * 7 + day * 2) * 86400)
                try? data.start(routineID: routine.id, now: date)
                if var session = data.activeSession {
                    for e in session.exercises.indices {
                        for s in session.exercises[e].sets.indices {
                            session.exercises[e].sets[s].completedAt = date.addingTimeInterval(Double(s * 90))
                            if let weight = session.exercises[e].sets[s].weight, session.exercises[e].sets[s].plan.kind != .warmup { session.exercises[e].sets[s].weight = weight + WeightUnit.lb.kilograms(Double(week * 2)) }
                        }
                    }
                    data.activeSession = session; try? data.finish(now: date.addingTimeInterval(2400))
                }
            }
        }
        return data
    }
}
