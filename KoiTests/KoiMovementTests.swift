import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiMovementTests: XCTestCase {
    func testExerciseScoreCombinesCappedStepsAndRollingTrainingCredit() {
        let restDay = ExerciseEngine.score(ExerciseDayInput(steps: 4_000, stepGoal: 8_000, isTrainingDay: false, workoutsInLastSevenDays: 2, weeklyWorkoutGoal: 4))
        XCTAssertEqual(restDay.stepScore, 0.5, accuracy: 0.0001)
        XCTAssertEqual(restDay.trainingScore, 0.5, accuracy: 0.0001)
        XCTAssertEqual(restDay.score, 0.5, accuracy: 0.0001)

        let trainingDay = ExerciseEngine.score(ExerciseDayInput(steps: 0, stepGoal: 8_000, isTrainingDay: true, workoutsInLastSevenDays: 1, weeklyWorkoutGoal: 4))
        XCTAssertEqual(trainingDay.trainingScore, 1)
        XCTAssertEqual(trainingDay.score, 0.5, accuracy: 0.0001)
    }

    func testMovementEntriesPersistAndManualStepsLayerOverHealthSteps() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = MovementViewModel()
        model.load(context)
        XCTAssertEqual(model.stepGoal, 8_000)
        XCTAssertEqual(model.weeklyWorkoutGoal, 4)

        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let provider = StubHealthProvider(samples: [
            HealthMovementSample(date: today, steps: 4_000, workoutCount: 0),
            HealthMovementSample(date: yesterday, steps: 6_000, workoutCount: 1)
        ])
        await model.connectHealth(using: provider)
        model.changeSteps(by: 1_000)
        model.toggleManualTraining()

        let todayRecord = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiMovementDay>()).first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }))
        XCTAssertEqual(todayRecord.healthSteps, 4_000)
        XCTAssertEqual(todayRecord.manualStepAdjustment, 1_000)
        XCTAssertTrue(todayRecord.didManuallyTrain)
        XCTAssertEqual(todayRecord.steps, 5_000)

        let reloaded = MovementViewModel()
        reloaded.load(context)
        XCTAssertEqual(reloaded.steps, 5_000)
        XCTAssertEqual(reloaded.workoutsThisWeek, 2)
        XCTAssertTrue(reloaded.isTrainingDay)
        XCTAssertTrue(reloaded.healthEnabled)
    }

    func testHubUsesMovementEventsForTodaysExercisePillar() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiMovementGoal())
        context.insert(KoiMovementDay(date: .now, healthSteps: 4_000, healthWorkoutCount: 2))
        try context.save()

        let hub = HubViewModel(publishesWidgetSnapshot: false)
        hub.refresh(using: context)
        XCTAssertEqual(hub.balance.exercise, 0.75, accuracy: 0.0001)
    }
}

@MainActor
private struct StubHealthProvider: HealthProviding {
    let samples: [HealthMovementSample]
    var isAvailable: Bool { true }
    func requestReadAccess() async throws {}
    func movementData(from start: Date, to end: Date, calendar: Calendar) async throws -> [HealthMovementSample] {
        samples.filter { $0.date >= start && $0.date < end }
    }
}
