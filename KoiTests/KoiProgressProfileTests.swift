import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiProgressProfileTests: XCTestCase {
    func testProfileFocusWeightAndMovementPreferencesPersist() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = ProfileViewModel()
        model.load(context)
        model.nameDraft = "Sam"
        model.saveName()
        model.setFocus(.mover)
        model.setWeight(181.3)
        model.saveWeightToday()
        model.setWeight(182.1)
        model.saveWeightToday()
        model.setMovementGoals(steps: 9_500, weeklyWorkouts: 5)

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<KoiProfile>()).first)
        XCTAssertEqual(profile.name, "Sam")
        XCTAssertEqual(profile.focusKey, BalanceFocus.mover.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).count, 1)
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).first).weightLB, 182.1, accuracy: 0.01)
        let movement = try XCTUnwrap(context.fetch(FetchDescriptor<KoiMovementGoal>()).first)
        XCTAssertEqual(movement.stepGoal, 9_500)
        XCTAssertEqual(movement.weeklyWorkoutGoal, 5)
    }

    func testProgressScoresSelectedDayUsingSavedFocusAndNutritionEvents() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: .now)
        context.insert(KoiProfile(name: "Mika", focusKey: BalanceFocus.ritualist.rawValue))
        let habit = KoiHabit(title: "Read", createdAt: today)
        context.insert(habit)
        context.insert(KoiHabitLog(habitID: habit.id, date: today, completion: 2))
        context.insert(KoiFoodEntry(name: "Lunch", loggedAt: .now, calories: 2_200, proteinGrams: 140, fiberGrams: 30))
        try context.save()

        let model = ProgressViewModel()
        model.load(context)
        model.select(today)

        XCTAssertEqual(model.currentSummary.days, 1)
        XCTAssertEqual(model.currentSummary.habitsDone, 1)
        XCTAssertEqual(model.currentSummary.habitsScheduled, 1)
        XCTAssertEqual(model.currentSummary.averageBalance, 0.6875, accuracy: 0.01)
        XCTAssertEqual(model.focusLabel, "The Ritualist")
        model.setScope(.week)
        XCTAssertNil(model.focusedDate)
        XCTAssertFalse(model.weekMetrics.isEmpty)
    }

    func testHubGreetingAndBalanceFollowProfile() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiProfile(name: "Sam", focusKey: BalanceFocus.ritualist.rawValue))
        context.insert(KoiDay(date: .now, habitsScore: 0.9, nutritionScore: 0.2, exerciseScore: 0.1))
        try context.save()

        let model = HubViewModel()
        model.refresh(using: context)

        XCTAssertTrue(model.greeting.contains("Sam"))
        XCTAssertEqual(model.balance.score, 0.525, accuracy: 0.01)
    }
}
