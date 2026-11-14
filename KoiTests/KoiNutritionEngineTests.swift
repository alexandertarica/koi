import XCTest
@testable import Koi

final class KoiNutritionEngineTests: XCTestCase {
    func testReachAroundAndLimitContributionsAreAveraged() {
        let result = NutritionEngine.score(
            goals: [
                NutrientGoalInput(key: "protein", goal: 100, type: .reach),
                NutrientGoalInput(key: "calories", goal: 2_000, type: .around),
                NutrientGoalInput(key: "sodium", goal: 2_000, type: .limit),
                NutrientGoalInput(key: "fat", goal: 70, type: .track)
            ],
            values: ["protein": 50, "calories": 1_000, "sodium": 1_000],
            calories: 1_000,
            calorieGoal: 2_000,
            hasAnyIntake: true
        )
        XCTAssertEqual(result.contributions["protein"] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.contributions["calories"] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.contributions["sodium"] ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(result.contributions["fat"])
        XCTAssertEqual(result.score, 0.5, accuracy: 0.0001)
    }

    func testLimitOverGoalAndReachAboveGoalAreCapped() {
        let result = NutritionEngine.score(
            goals: [NutrientGoalInput(key: "protein", goal: 50, type: .reach), NutrientGoalInput(key: "sodium", goal: 1_000, type: .limit)],
            values: ["protein": 100, "sodium": 2_000],
            calories: 2_000,
            calorieGoal: 2_000,
            hasAnyIntake: true
        )
        XCTAssertEqual(result.contributions["protein"] ?? -1, 1)
        XCTAssertEqual(result.contributions["sodium"] ?? -1, 0.5)
        XCTAssertEqual(result.score, 0.75, accuracy: 0.0001)
    }

    func testUntouchedDayScoresZeroAndTotalsCombineMealsWithAdjustments() {
        let meals = [MealNutritionInput(calories: 500, protein: 20, carbs: 40, fat: 15, fiber: 5, addedSugar: 3, sodium: 400)]
        XCTAssertFalse(NutritionEngine.hasAnyIntake(meals: [], adjustments: []))
        XCTAssertEqual(NutritionEngine.score(goals: [], values: [:], calories: 0, calorieGoal: 2_000, hasAnyIntake: false).score, 0)
        let values = NutritionEngine.totals(meals: meals, adjustments: [NutritionAdjustmentInput(key: "protein", value: 5), NutritionAdjustmentInput(key: "water", value: 16)])
        XCTAssertEqual(values["protein"], 25)
        XCTAssertEqual(values["calories"], 500)
        XCTAssertEqual(values["water"], 16)
    }
}
