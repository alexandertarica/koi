import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiIntakeTests: XCTestCase {
    func testDefaultGoalsMealAndManualAdjustmentPersist() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = IntakeViewModel()
        model.load(context)

        XCTAssertEqual(model.activeGoals.count, 4)
        let meal = FoodEstimateValue(description: "Oat bowl", calories: 420, proteinGrams: 18, carbohydrateGrams: 55, fatGrams: 12, fiberGrams: 9, addedSugarGrams: 4, sodiumMilligrams: 210, confidence: 0.8)
        model.addMeal(meal, note: "Oats, berries, yogurt", jpegData: nil)
        model.setValue("water", to: 24)

        let storedMeal = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiFoodEntry>()).first)
        let storedAdjustment = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiNutrientEntry>()).first)
        XCTAssertEqual(storedMeal.name, "Oat bowl")
        XCTAssertEqual(storedMeal.notes, "Oats, berries, yogurt")
        XCTAssertEqual(storedMeal.calories, 420)
        XCTAssertEqual(storedAdjustment.nutrientKey, "water")
        XCTAssertEqual(model.calories, 420)
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "water" })?.value, 24)

        model.updateMeal(storedMeal, value: FoodEstimateValue(description: "Oat bowl", calories: 450, proteinGrams: 20, carbohydrateGrams: 56, fatGrams: 12, fiberGrams: 9, addedSugarGrams: 4, sodiumMilligrams: 210, confidence: 0.9), note: "With banana", jpegData: nil)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiFoodEntry>()).first?.calories, 450)
        model.deleteMeal(storedMeal)
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiFoodEntry>()).isEmpty)
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "water" })?.value, 24)
    }

    func testHubUsesMealEventsForTodaysNutritionPillar() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let intake = IntakeViewModel()
        intake.load(context)
        intake.addMeal(FoodEstimateValue(description: "Day of food", calories: 2_200, proteinGrams: 140, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 30, addedSugarGrams: 0, sodiumMilligrams: 0, confidence: 1), note: "", jpegData: nil)

        let hub = HubViewModel(publishesWidgetSnapshot: false)
        hub.refresh(using: context)
        XCTAssertEqual(hub.balance.nutrition, 0.75, accuracy: 0.0001)
    }
}
