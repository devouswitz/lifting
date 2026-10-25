import Foundation

public extension TrainingData {
    /// Sample library for screenshots and demos: a finished 5/3/1 block, then Push Pull Legs as the
    /// current program, with about four months of workouts logged through the training engine.
    static func showcase(now: Date = Date()) -> TrainingData {
        var data = starter()
        data.routines = []; data.variants = []; data.programs = []; data.activeProgramID = nil
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -weekday, to: today)!
        func day(weeksAgo: Int, offset: Int) -> Date { calendar.date(byAdding: .day, value: offset - weeksAgo * 7, to: thisMonday)! }
        func lb(_ pounds: Double) -> Double { WeightUnit.lb.kilograms(pounds) }
        func exercise(_ name: String) -> Exercise { data.exercises.first { $0.name == name }! }
        var seed: UInt64 = 0x5EED
        func roll(_ range: ClosedRange<Int>) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return range.lowerBound + Int((seed >> 33) % UInt64(range.count))
        }

        let backOff = CustomSetType(name: "Back-off", badge: "B", countsAs: .working)
        data.customSetTypes = [backOff]
        data.settings.quickAdd = ["drop", "type:\(backOff.id.uuidString)"]

        /// How a lift moves between sessions: reps climb through the range, then weight goes up.
        struct Plan { var weight: Double; var low: Int; var high: Int; var step: Double; var every = 1; var count = 0; var reps: Int }
        var plans: [UUID: Plan] = [:]
        func warmups(_ steps: [(Double, Int)]) -> [SetPlan] { steps.map { SetPlan(kind: .warmup, load: .percent, percent: $0.0, reps: $0.1, repCeiling: nil) } }
        func sets(_ count: Int, _ low: Int, _ high: Int? = nil, load: LoadRule = .working) -> [SetPlan] {
            (0..<count).map { _ in SetPlan(load: load, reps: low, repCeiling: high) }
        }
        func slot(_ name: String, _ label: String, pounds: Double, rest: Int, sets prescription: [SetPlan], notes: String = "", range: (Int, Int)? = nil, step: Double = 5, every: Int = 1, rounding: Double = 2.5) -> RoutineSlot {
            let lift = exercise(name)
            let variant = Variant(exerciseID: lift.id, label: label, workingWeight: lb(pounds), rounding: lb(rounding), restSeconds: rest, notes: notes, sets: prescription)
            data.variants.append(variant)
            if let range { plans[variant.id] = Plan(weight: pounds, low: range.0, high: range.1, step: step, every: every, reps: range.0) }
            return RoutineSlot(variantID: variant.id)
        }
        func link(_ routine: inout Routine, _ first: Int, _ second: Int, rest: Int) {
            let key = UUID().uuidString
            for index in [first, second] { routine.slots[index].group = key; routine.slots[index].groupRestSeconds = rest; routine.slots[index].transitionSeconds = 0 }
        }

        // Push Pull Legs, the current program.
        var push = Routine(name: "Push", slots: [
            slot("Bench press", "Push", pounds: 175, rest: 180, sets: warmups([(50, 5), (75, 3)]) + sets(4, 6, 8), notes: "Pause the first rep.", range: (6, 8)),
            slot("Overhead press", "Push", pounds: 95, rest: 150, sets: sets(3, 8, 10), range: (8, 10)),
            slot("Incline dumbbell press", "Push", pounds: 55, rest: 120, sets: sets(3, 8, 12), range: (8, 12)),
            slot("Cable lateral raise", "Push", pounds: 15, rest: 60, sets: sets(3, 12, 15) + [SetPlan(kind: .drop, load: .percent, percent: 70, reps: 12, repCeiling: nil)], range: (12, 15), step: 2.5, rounding: 2.5),
            slot("Triceps pressdown", "Push", pounds: 50, rest: 60, sets: sets(3, 10, 12), range: (10, 12))
        ])
        link(&push, 3, 4, rest: 90)
        var pull = Routine(name: "Pull", slots: [
            slot("Barbell row", "Pull", pounds: 145, rest: 150, sets: warmups([(60, 5)]) + sets(4, 6, 8), range: (6, 8)),
            slot("Pull-up", "Pull", pounds: 0, rest: 120, sets: sets(3, 6, 10, load: .none), range: (6, 10), step: 0),
            slot("Lat pulldown", "Pull", pounds: 110, rest: 90, sets: sets(3, 10, 12), range: (10, 12)),
            slot("Face pull", "Pull", pounds: 35, rest: 60, sets: sets(3, 15, 20), range: (15, 20)),
            slot("Hammer curl", "Pull", pounds: 30, rest: 60, sets: sets(3, 10, 12), range: (10, 12), step: 2.5)
        ])
        link(&pull, 3, 4, rest: 90)
        let backOffSets = (0..<3).map { _ -> SetPlan in var plan = SetPlan(load: .percent, percent: 85, reps: 8, repCeiling: nil); plan.customTypeID = backOff.id; return plan }
        let legs = Routine(name: "Legs", slots: [
            slot("Squat", "Legs", pounds: 235, rest: 180, sets: warmups([(40, 5), (60, 3), (80, 2)]) + sets(1, 5) + backOffSets, notes: "Belt on the top set.", range: (5, 5), step: 5, every: 2, rounding: 5),
            slot("Romanian deadlift", "Legs", pounds: 185, rest: 150, sets: sets(3, 8, 10), range: (8, 10), step: 10, rounding: 5),
            slot("Leg press", "Legs", pounds: 320, rest: 120, sets: sets(3, 10, 15), range: (10, 15), step: 20, rounding: 10),
            slot("Leg curl", "Legs", pounds: 80, rest: 90, sets: sets(3, 10, 12), range: (10, 12)),
            slot("Calf raise", "Legs", pounds: 160, rest: 60, sets: sets(4, 12, 15), range: (12, 15), step: 10)
        ])

        // 5/3/1 Boring But Big: main sets from the training max, then 5 × 10 at 50%.
        func fiveThreeOne(_ name: String, _ label: String, max pounds: Double, accessory: RoutineSlot) -> Routine {
            let main = warmups([(40, 5), (50, 5)]) + [SetPlan(load: .percent, percent: 65, reps: 5, repCeiling: nil), SetPlan(load: .percent, percent: 75, reps: 5, repCeiling: nil), SetPlan(load: .percent, percent: 85, reps: 5, repCeiling: nil, amrap: true)]
                + (0..<5).map { _ in SetPlan(load: .percent, percent: 50, reps: 10, repCeiling: nil) }
            return Routine(name: label, slots: [slot(name, label, pounds: pounds, rest: 180, sets: main, rounding: 5), accessory])
        }
        let press = fiveThreeOne("Overhead press", "Press", max: 100, accessory: slot("Chin-up", "Press", pounds: 0, rest: 90, sets: sets(5, 10, load: .none)))
        let pullDay = fiveThreeOne("Deadlift", "Deadlift", max: 315, accessory: slot("Hanging leg raise", "Deadlift", pounds: 0, rest: 60, sets: sets(5, 10, load: .none)))
        let bench = fiveThreeOne("Bench press", "Bench", max: 185, accessory: slot("Chest-supported row", "Bench", pounds: 50, rest: 90, sets: sets(5, 10)))
        let squat = fiveThreeOne("Squat", "Squat", max: 255, accessory: slot("Leg curl", "Squat", pounds: 70, rest: 90, sets: sets(5, 10)))

        // Templates kept outside any program.
        var arms = Routine(name: "Arms", slots: [
            slot("Cable curl", "Arms", pounds: 40, rest: 60, sets: sets(3, 10, 12)),
            slot("Overhead triceps extension", "Arms", pounds: 40, rest: 60, sets: sets(3, 10, 12))
        ])
        link(&arms, 0, 1, rest: 75)
        let row = exercise("Row"), bike = exercise("Bike")
        let rowing = Variant(exerciseID: row.id, label: "Conditioning", restSeconds: 0, sets: [SetPlan(load: .none, reps: nil, repCeiling: nil, seconds: 600, meters: 2000)])
        let biking = Variant(exerciseID: bike.id, label: "Conditioning", restSeconds: 0, sets: [SetPlan(load: .none, reps: nil, repCeiling: nil, seconds: 1200, rpe: 6)])
        data.variants += [rowing, biking]
        let conditioning = Routine(name: "Conditioning", slots: [RoutineSlot(variantID: rowing.id), RoutineSlot(variantID: biking.id)])

        data.routines = [press, pullDay, bench, squat, push, pull, legs, arms, conditioning]
        let block = TrainingProgram(name: "5/3/1 Boring But Big", notes: "Four-week waves. Raise the training max after each wave.", dayIDs: [press.id, pullDay.id, bench.id, squat.id])
        let ppl = TrainingProgram(name: "Push Pull Legs", notes: "Five days a week. Add weight once every set reaches the top of the range.", dayIDs: [push.id, pull.id, legs.id])
        data.programs = [ppl, block]

        func log(_ routine: Routine, on date: Date, note: String = "", adjust: (inout Session, Int) -> Void = { _, _ in }) {
            for (id, plan) in plans { if let v = data.variants.firstIndex(where: { $0.id == id }) { data.variants[v].workingWeight = lb(plan.weight) } }
            let start = date.addingTimeInterval(Double(17 * 3600 + roll(0...5) * 600))
            guard (try? data.start(routineID: routine.id, now: start)) != nil, var session = data.activeSession else { return }
            var clock = start.addingTimeInterval(300)
            for e in session.exercises.indices {
                let plan = plans[session.exercises[e].variantID]
                let top = session.exercises[e].sets.indices.last { session.exercises[e].sets[$0].plan.kind != .warmup && session.exercises[e].sets[$0].plan.load != .percent }
                for s in session.exercises[e].sets.indices {
                    var set = session.exercises[e].sets[s]
                    if set.plan.kind == .warmup || set.plan.load == .percent || plan == nil {
                        set.reps = set.reps ?? set.plan.reps
                    } else if let plan {
                        let last = s == top
                        set.reps = max(plan.low - 1, plan.reps - (last && plan.low < plan.high && roll(0...3) == 0 ? 1 : 0))
                        if last && session.exercises[e].restSeconds >= 150 { set.rpe = [7.5, 8, 8.5, 9][roll(0...3)] }
                    }
                    if set.plan.kind == .drop { set.reps = max(8, (set.plan.reps ?? 10) - roll(0...3)) }
                    clock = clock.addingTimeInterval(Double((set.plan.restSeconds ?? session.exercises[e].restSeconds) + 35 + roll(0...20)))
                    set.completedAt = clock
                    session.exercises[e].sets[s] = set
                }
                clock = clock.addingTimeInterval(90)
            }
            adjust(&session, roll(0...3))
            session.notes = note
            data.activeSession = session
            try? data.finish(now: clock.addingTimeInterval(60))
            for item in session.exercises {
                guard var plan = plans[item.variantID] else { continue }
                plan.count += 1
                if plan.low == plan.high { if plan.count % plan.every == 0 { plan.weight += plan.step } }
                else if plan.reps < plan.high { plan.reps += 1 }
                else if plan.step > 0 { plan.reps = plan.low; plan.weight += plan.step }
                plans[item.variantID] = plan
            }
        }

        // The 5/3/1 block: two waves, Monday, Tuesday, Thursday, Saturday.
        try? data.loadProgram(block.id)
        let waves: [[(Double, Int)]] = [[(65, 5), (75, 5), (85, 5)], [(70, 3), (80, 3), (90, 3)], [(75, 5), (85, 3), (95, 1)], [(40, 5), (50, 5), (60, 5)]]
        let maxes: [UUID: [Double]] = [press.id: [100, 105], pullDay.id: [315, 325], bench.id: [185, 190], squat.id: [255, 265]]
        for week in 0..<8 {
            for (offset, routine) in zip([0, 1, 3, 5], [press, pullDay, bench, squat]) {
                let trainingMax = maxes[routine.id]![week / 4]
                let wave = waves[week % 4]
                let note = week == 7 && routine.id == squat.id ? "Last deload of the block." : ""
                log(routine, on: day(weeksAgo: 16 - week, offset: offset), note: note) { session, extra in
                    let main = session.exercises[0].sets.indices.filter { session.exercises[0].sets[$0].plan.kind != .warmup }
                    for (index, s) in main.enumerated() {
                        if index < 3 {
                            session.exercises[0].sets[s].weight = lb((trainingMax * wave[index].0 / 100 / 5).rounded(.down) * 5)
                            session.exercises[0].sets[s].reps = wave[index].1 + (index == 2 && week % 4 != 3 ? 2 + extra : 0)
                        } else {
                            session.exercises[0].sets[s].weight = lb((trainingMax * (week % 4 == 3 ? 40 : 50) / 100 / 5).rounded(.down) * 5)
                            if s == main.last, extra == 0 { session.exercises[0].sets[s].reps = 8 }
                        }
                    }
                    if session.exercises.count > 1, session.exercises[1].mode == .bodyweight {
                        for s in session.exercises[1].sets.indices { session.exercises[1].sets[s].reps = max(6, 10 - s / 2 - (extra == 0 ? 1 : 0)) }
                    }
                }
            }
        }

        // Push Pull Legs: Monday, Tuesday, Wednesday, Friday, Saturday, ending before today.
        try? data.loadProgram(ppl.id)
        var dates = (0...7).reversed().flatMap { weeks in [0, 1, 2, 4, 5].map { day(weeksAgo: weeks, offset: $0) } }.filter { $0 < today }
        dates.removeFirst(dates.count % 3)
        let skip = dates.count - 9
        for (index, date) in dates.enumerated() {
            if index == skip { try? data.skipNextDay(in: ppl.id, now: date.addingTimeInterval(18 * 3600)); continue }
            let routine = [push, pull, legs][index % 3]
            let note = index == 0 ? "First week of Push Pull Legs." : index == dates.count - 4 ? "Gym was packed, did leg press before RDLs." : ""
            log(routine, on: date, note: note)
        }
        for (id, plan) in plans { if let v = data.variants.firstIndex(where: { $0.id == id }) { data.variants[v].workingWeight = lb(plan.weight) } }
        for (routine, max) in [(press, 110.0), (pullDay, 335), (bench, 195), (squat, 275)] {
            if let id = routine.slots.first?.variantID, let v = data.variants.firstIndex(where: { $0.id == id }) { data.variants[v].workingWeight = lb(max) }
        }
        // Morning weigh-ins most days, drifting from 184 to 181 lb with day-to-day noise. Added after the
        // workouts so the logged bodyweight loads stay as they were.
        data.bodyWeights = (0..<112).compactMap { daysAgo -> BodyWeightEntry? in
            guard daysAgo % 7 != 3, daysAgo % 11 != 5, let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)?.addingTimeInterval(7 * 3600) else { return nil }
            let trend = 181.2 + 2.8 * Double(daysAgo) / 111
            let noise = sin(Double(daysAgo) * 1.7) * 0.7 + cos(Double(daysAgo) * 0.6) * 0.4
            return BodyWeightEntry(date: date, kilograms: lb(((trend + noise) * 10).rounded() / 10))
        }.reversed()
        return data
    }
}
