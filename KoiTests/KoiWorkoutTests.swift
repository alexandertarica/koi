import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiWorkoutTests: XCTestCase {
    func testLiftGroupingBodyweightAndDoubleProgression() {
        XCTAssertEqual(WorkoutNameRules.guessGroup("Dumbbell bench press"), "push")
        XCTAssertEqual(WorkoutNameRules.guessGroup("Lat pulldown"), "pull")
        XCTAssertEqual(WorkoutNameRules.guessGroup("Goblet squat"), "legs")
        XCTAssertTrue(WorkoutNameRules.isBodyweight("Push-up"))

        let nextWeight = WorkoutEngine.nextStep(lastSets: [
            WorkoutSetResult(weightLB: 40, reps: 8, estimatedOneRepMax: nil),
            WorkoutSetResult(weightLB: 40, reps: 8, estimatedOneRepMax: nil)
        ], targetReps: 8, isBodyweight: false)
        XCTAssertEqual(nextWeight?.weightLB, 42.5)
        XCTAssertEqual(nextWeight?.reps, 8)
        let incomplete = WorkoutEngine.nextStep(lastSets: [
            WorkoutSetResult(weightLB: 40, reps: 12, estimatedOneRepMax: nil),
            WorkoutSetResult(weightLB: 40, reps: 12, estimatedOneRepMax: nil)
        ], targetReps: 12, targetSets: 3, isBodyweight: false)
        XCTAssertEqual(incomplete?.weightLB, 40)
        let recoveryHold = WorkoutEngine.nextStep(lastSets: [WorkoutSetResult(weightLB: 100, reps: 12, estimatedOneRepMax: nil)], targetReps: 8, targetSets: 3, isBodyweight: false, holdWeight: true)
        XCTAssertEqual(recoveryHold?.weightLB, 100)
        XCTAssertEqual(recoveryHold?.reason, "Recovery is low. Hold your usual weight.")

        let nextReps = WorkoutEngine.nextStep(lastSets: [
            WorkoutSetResult(weightLB: 0, reps: 10, estimatedOneRepMax: nil),
            WorkoutSetResult(weightLB: 0, reps: 10, estimatedOneRepMax: nil)
        ], targetReps: 10, isBodyweight: true)
        XCTAssertEqual(nextReps?.weightLB, 0)
        XCTAssertEqual(nextReps?.reps, 11)
        XCTAssertEqual(WorkoutEngine.estimatedOneRepMax(weightLB: 100, reps: 10), 100 * (1 + 10.0 / 30))
        XCTAssertNil(WorkoutEngine.estimatedOneRepMax(weightLB: 0, reps: 10, isBodyweight: true))
    }

    func testReadinessUsesAvailableBaselinesAndExplainsLowRecovery() {
        XCTAssertNil(ReadinessEngine.evaluate(ReadinessInput(sleepHours: nil, sleepBaselineHours: nil, hrv: nil, hrvBaseline: nil, restingHeartRate: nil, restingHeartRateBaseline: nil)))
        let ready = ReadinessEngine.evaluate(ReadinessInput(sleepHours: 8, sleepBaselineHours: 7.5, hrv: 55, hrvBaseline: 50, restingHeartRate: 58, restingHeartRateBaseline: 60))
        XCTAssertEqual(ready?.level, .ready)
        let easy = ReadinessEngine.evaluate(ReadinessInput(sleepHours: 5, sleepBaselineHours: 7, hrv: 35, hrvBaseline: 50, restingHeartRate: 62, restingHeartRateBaseline: 60))
        XCTAssertEqual(easy?.level, .takeItEasy)
        XCTAssertEqual(easy?.reasons.count, 2)
    }

    func testPlateMathUsesLargestAvailablePlatesAndReportsNearestLoad() {
        let exact = PlateMath.load(weight: 185, bar: 45)
        XCTAssertEqual(exact.platesPerSide, [45, 25])
        XCTAssertTrue(exact.isExact)
        let nearest = PlateMath.load(weight: 182, bar: 45)
        XCTAssertFalse(nearest.isExact)
        XCTAssertEqual(nearest.usableWeight, 180)
    }

    func testSmartNoteRecognizesMealWaterToDoAndSets() {
        XCTAssertEqual(SmartNoteParser.parse("oatmeal with berries"), .food("oatmeal with berries"))
        XCTAssertNil(SmartNoteParser.parse("Walked to coffee"))
        XCTAssertTrue(SmartNoteParser.isActivityWithoutFood("Walked to coffee"))
        XCTAssertFalse(SmartNoteParser.isActivityWithoutFood("Walked, then had coffee"))
        XCTAssertEqual(SmartNoteParser.parse("drank 12 oz water"), .water(12))
        guard case let .workout(name, weight, reps, sets)? = SmartNoteParser.parse("bench press 185x5x3") else {
            return XCTFail("Expected a logged workout")
        }
        XCTAssertEqual(name, "bench press")
        XCTAssertEqual(weight, 185)
        XCTAssertEqual(reps, 5)
        XCTAssertEqual(sets, 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z") ?? Date(timeIntervalSince1970: 0)
        guard case let .task(title, dueAt)? = SmartNoteParser.parse("todo call dentist tomorrow", now: now, calendar: calendar) else {
            return XCTFail("Expected a scheduled to-do")
        }
        XCTAssertEqual(title, "todo call dentist tomorrow")
        XCTAssertEqual(calendar.component(.day, from: dueAt ?? .distantPast), 15)
    }

    func testHabitCoachOffersGraduationThenStepUpAndEaseOff() {
        let graduation = HabitCoachEngine.suggestion([HabitCoachInput(scheduledDays: 70, completedDays: 65, minimumDays: 0, consecutiveStrongWeeks: 4, activeDays: 70, strongestHabitTitle: "Walk")])
        XCTAssertEqual(graduation?.action, .graduate)
        let stepUp = HabitCoachEngine.suggestion([HabitCoachInput(scheduledDays: 28, completedDays: 26, minimumDays: 0, consecutiveStrongWeeks: 4, activeDays: 28, strongestHabitTitle: "Walk")])
        XCTAssertEqual(stepUp?.action, .stepUp(minimum: "Keep the current amount as your minimum."))
        let easeOff = HabitCoachEngine.suggestion([HabitCoachInput(scheduledDays: 14, completedDays: 5, minimumDays: 4, consecutiveStrongWeeks: 0, activeDays: 14, strongestHabitTitle: nil)])
        XCTAssertEqual(easeOff?.action, .easeOff)
    }

    func testRecommendationHonorsPlannedRoutineAndRestAfterThreeDays() {
        let planned = WorkoutRoutineSummary(id: UUID(), name: "Upper A", muscleGroup: "upper", plannedAt: .now)
        let plannedResult = WorkoutEngine.recommend(WorkoutRecommendationInput(groupLastTrained: [:], lastRoutineNameByGroup: [:], consecutiveTrainingDays: 3, plannedRoutine: planned, routines: [planned]))
        XCTAssertEqual(plannedResult.routine?.name, "Upper A")
        XCTAssertFalse(plannedResult.suggestsRest)

        let restResult = WorkoutEngine.recommend(WorkoutRecommendationInput(groupLastTrained: [:], lastRoutineNameByGroup: [:], consecutiveTrainingDays: 3, plannedRoutine: nil, routines: []))
        XCTAssertTrue(restResult.suggestsRest)

        let upperA = WorkoutRoutineSummary(id: UUID(), name: "Upper A", muscleGroup: "upper", plannedAt: nil)
        let upperB = WorkoutRoutineSummary(id: UUID(), name: "Upper B", muscleGroup: "upper", plannedAt: nil)
        let trainedRecently = Date.now
        let alternate = WorkoutEngine.recommend(WorkoutRecommendationInput(groupLastTrained: ["push": trainedRecently, "pull": trainedRecently, "legs": trainedRecently, "core": trainedRecently], lastRoutineNameByGroup: ["upper": "Upper A"], consecutiveTrainingDays: 0, plannedRoutine: nil, routines: [upperA, upperB]))
        XCTAssertEqual(alternate.routine?.name, "Upper B")
    }

    func testRoutineSessionSetsRestSummaryAndMovementTrainingPersist() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WorkoutViewModel()
        model.load(context)
        model.saveRoutine(existing: nil, name: "Push day", liftNames: ["Bench press"], plannedAt: nil, startNow: false)
        let routine = try XCTUnwrap(model.routines.first)
        model.startRoutine(routine)

        XCTAssertEqual(model.activeLifts.count, 1)
        model.setWeight(100)
        model.setReps(8)
        model.logSet()
        XCTAssertTrue(model.isResting)
        XCTAssertTrue(model.isNewBest)
        model.skipRest()
        model.logSet(isWarmUp: true)
        XCTAssertEqual(model.currentSets.count, 2)

        let summary = try XCTUnwrap(model.endSession())
        XCTAssertEqual(summary.name, "Push day")
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.volumeLB, 800)
        XCTAssertEqual(summary.bestLifts, ["Bench press"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiWorkoutSession>()).first?.isComplete ?? false)
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiMovementDay>()).first?.didManuallyTrain ?? false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiWorkoutSet>()).count, 2)
    }

    func testImportedRoutinePreservesPerExerciseTargetsAndSupersetAlternatesBeforeRest() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WorkoutViewModel()
        model.load(context)
        let imported = ImportedRoutine(name: "Upper A", exercises: [ImportedExercise(name: "Bench press", sets: 4, reps: 6), ImportedExercise(name: "Seated row", sets: 3, reps: 10)])
        model.saveImportedRoutine(imported, plannedAt: nil, startNow: false)
        let routine = try XCTUnwrap(model.routines.first)
        let templates = try context.fetch(FetchDescriptor<KoiRoutineLift>()).sorted { $0.order < $1.order }
        XCTAssertEqual(templates.map(\.targetSets), [4, 3])
        XCTAssertEqual(templates.map(\.targetReps), [6, 10])

        model.startRoutine(routine)
        let lifts = model.activeLifts
        model.pairWithNext(lifts[0])
        model.selectLift(lifts[1].id)
        model.selectLift(lifts[0].id)
        model.logSet()
        XCTAssertEqual(model.currentLift?.id, lifts[1].id)
        XCTAssertFalse(model.isResting)
        model.logSet()
        XCTAssertEqual(model.currentLift?.id, lifts[0].id)
        XCTAssertTrue(model.isResting)
    }
}
