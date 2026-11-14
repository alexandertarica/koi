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

        let nextReps = WorkoutEngine.nextStep(lastSets: [
            WorkoutSetResult(weightLB: 0, reps: 10, estimatedOneRepMax: nil),
            WorkoutSetResult(weightLB: 0, reps: 10, estimatedOneRepMax: nil)
        ], targetReps: 10, isBodyweight: true)
        XCTAssertEqual(nextReps?.weightLB, 0)
        XCTAssertEqual(nextReps?.reps, 11)
        XCTAssertEqual(WorkoutEngine.estimatedOneRepMax(weightLB: 100, reps: 10), 100 * (1 + 10.0 / 30))
        XCTAssertNil(WorkoutEngine.estimatedOneRepMax(weightLB: 0, reps: 10, isBodyweight: true))
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
}
