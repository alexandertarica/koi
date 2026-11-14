import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiOnboardingTests: XCTestCase {
    func testCompletionPersistsProfileHabitsTargetsAndTourState() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingViewModel()
        model.load(context)
        model.name = "  Sam  "
        model.focus = .mover
        model.stepGoal = 9_500
        model.weeklyWorkoutGoal = 5
        model.startingWeightLB = 161.5
        model.hasAboutDetails = true
        model.finish()

        XCTAssertTrue(model.isCompleted)
        XCTAssertTrue(model.shouldShowTour)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Sam")
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.focusKey, BalanceFocus.mover.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiHabit>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiMovementGoal>()).first?.stepGoal, 9_500)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiMovementGoal>()).first?.weeklyWorkoutGoal, 5)
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).first).weightLB, 161.5, accuracy: 0.01)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiNutrientGoal>()).count, 4)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).isComplete)

        model.markTourSeen()
        XCTAssertFalse(model.shouldShowTour)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).hasSeenTour)
    }

    func testOnboardingRequiresNameAndThreeSelectedHabits() {
        let model = OnboardingViewModel()
        model.advance()
        XCTAssertEqual(model.step, .name)
        XCTAssertFalse(model.canContinue)
        model.name = "Mika"
        model.advance()
        XCTAssertEqual(model.step, .focus)
        model.advance()
        XCTAssertEqual(model.step, .habits)
        for habit in model.habits.prefix(1) { model.toggleHabit(habit.id) }
        XCTAssertFalse(model.canContinue)
        model.toggleHabit(model.habits[0].id)
        XCTAssertTrue(model.canContinue)
        model.goBack()
        XCTAssertEqual(model.step, .focus)
    }

    func testSkipUsesDefaultsAndCompletesSetup() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingViewModel()
        model.load(context)
        model.skipToDefaults()

        XCTAssertTrue(model.isCompleted)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.focusKey, BalanceFocus.allRounder.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiHabit>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiMovementGoal>()).first?.stepGoal, 8_000)
    }

    func testQuickSetupStartsWithAnEmptyHubAndKeepsTheTourOptional() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingViewModel()
        model.load(context)
        model.name = "Ari"
        model.focus = .nourisher
        model.wantsHealth = true
        model.wantsCalendar = true
        model.finishQuickSetup()

        XCTAssertTrue(model.isCompleted)
        XCTAssertFalse(model.shouldShowTour)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiHabit>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiTask>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.focusKey, BalanceFocus.nourisher.rawValue)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiMovementGoal>()).first?.stepGoal, 8_000)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).healthConnected)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).calendarConnected)
    }
}
