import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiIntakeTests: XCTestCase {
    func testEstimateDecodesEveryServerNutrientField() throws {
        let data = Data(#"{"calories":612,"protein_g":31.5,"carbs_g":72,"fat_g":18,"fiber_g":11,"added_sugar_g":6,"sodium_mg":840}"#.utf8)
        let estimate = try JSONDecoder().decode(EstimateResponse.self, from: data).value

        XCTAssertEqual(estimate.description, "Meal")
        XCTAssertEqual(estimate.calories, 612)
        XCTAssertEqual(estimate.proteinGrams, 31.5)
        XCTAssertEqual(estimate.carbohydrateGrams, 72)
        XCTAssertEqual(estimate.fatGrams, 18)
        XCTAssertEqual(estimate.fiberGrams, 11)
        XCTAssertEqual(estimate.addedSugarGrams, 6)
        XCTAssertEqual(estimate.sodiumMilligrams, 840)
        XCTAssertEqual(estimate.confidence, 0.5)
    }

    func testCameraFallbackExplainsSimulatorLimitAndKeepsManualPathAvailable() {
        let model = IntakeViewModel()
        model.showCameraUnavailable()
        XCTAssertEqual(model.errorMessage, "The camera isn't available in Simulator. Choose a photo instead.")
        model.clearEstimate()
        XCTAssertNil(model.errorMessage)
    }

    func testPhotoOnlyEstimatePassesImageAndSavesOneMeal() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = IntakeViewModel()
        model.load(context)
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let estimate = FoodEstimateValue(description: "Protein bar", calories: 210, proteinGrams: 20, carbohydrateGrams: 24, fatGrams: 7, fiberGrams: 5, addedSugarGrams: 6, sodiumMilligrams: 180, confidence: 0.82)
        let estimator = PhotoOnlyFoodEstimator(value: estimate)

        await model.estimateMeal(text: nil, jpegData: jpeg, using: estimator)
        let decoded = try XCTUnwrap(model.estimate)
        let receivedPhoto = await estimator.receivedPhoto()
        XCTAssertEqual(decoded, estimate)
        XCTAssertEqual(receivedPhoto, jpeg)

        let saved = try XCTUnwrap(model.addMeal(decoded, note: "", jpegData: jpeg))
        XCTAssertEqual(saved.imageJPEG, jpeg)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiFoodEntry>()).count, 1)
        XCTAssertEqual(model.calories, 210)
    }

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
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "protein" })?.value, 18)
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "water" })?.value, 24)

        model.updateMeal(storedMeal, value: FoodEstimateValue(description: "Oat bowl", calories: 450, proteinGrams: 20, carbohydrateGrams: 56, fatGrams: 12, fiberGrams: 9, addedSugarGrams: 4, sodiumMilligrams: 210, confidence: 0.9), note: "With banana", jpegData: nil)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiFoodEntry>()).first?.calories, 450)
        XCTAssertEqual(model.calories, 450)
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "protein" })?.value, 20)
        model.deleteMeal(storedMeal)
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiFoodEntry>()).isEmpty)
        XCTAssertEqual(model.calories, 0)
        XCTAssertEqual(model.nutrientRows.first(where: { $0.key == "protein" })?.value, 0)
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

    func testCoachProteinTargetIsTodayOnlyAndVisibleInIntake() throws {
        DailyGoalAdjustment.clear("protein")
        defer { DailyGoalAdjustment.clear("protein") }
        DailyGoalAdjustment.holdBalance(0.62)
        DailyGoalAdjustment.add(10, to: "protein")

        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let intake = IntakeViewModel()
        intake.load(context)

        XCTAssertEqual(intake.nutrientRows.first(where: { $0.key == "protein" })?.goal, 150)
        XCTAssertEqual(intake.adjustmentNote, "Adjusted for today's workout")
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiNutrientGoal>()).first(where: { $0.key == "protein" })?.goal, 140)
    }

    func testCoachSchedulesBeforeFirstTomorrowCalendarEvent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let classTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let event = CalendarEventSummary(title: "Class", start: classTime, end: classTime.addingTimeInterval(3_600))
        let planned = HubViewModel.planTomorrowSlot(firstEvent: event, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: planned), 7)
        XCTAssertLessThanOrEqual(planned.addingTimeInterval(30 * 60), classTime)
    }

    func testCoachSchedulesTomorrowLocallyInsteadOfUsingModelDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let ancientModelDate = calendar.date(from: DateComponents(year: 2023, month: 10, day: 4, hour: 7))!
        let planned = HubViewModel.planTomorrowSlot(firstEvent: nil, calendar: calendar)

        XCTAssertNotEqual(planned, ancientModelDate)
        XCTAssertEqual(calendar.startOfDay(for: planned), tomorrow)
        XCTAssertEqual(calendar.component(.hour, from: planned), 7)
        XCTAssertEqual(calendar.component(.minute, from: planned), 0)
    }

    func testAcceptingCoachGoalActionLeavesBalanceAndRecurringGoalAlone() async throws {
        DailyGoalAdjustment.clear("protein")
        defer { DailyGoalAdjustment.clear("protein") }
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiDay(date: .now, balance: 0.75, habitsScore: 0.75, nutritionScore: 0.75, exerciseScore: 0.75))
        try context.save()
        let suggestion = KoiCoachSuggestion(message: "Add a little protein today.", action: KoiCoachAction(type: .adjustGoal, nutrient: "protein", delta: 10, why: "Support training."))
        let model = HubViewModel(publishesWidgetSnapshot: false, coachProvider: FixedCoachProvider(suggestion: suggestion))
        model.refresh(using: context)
        await model.requestCoach(event: "workout", using: FakeCoachCalendar())
        await model.acceptCoach(using: FakeCoachCalendar())

        let intake = IntakeViewModel()
        intake.load(context)
        XCTAssertEqual(model.balance.score, 0.75, accuracy: 0.0001)
        XCTAssertEqual(intake.nutrientRows.first(where: { $0.key == "protein" })?.goal, 150)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiNutrientGoal>()).first(where: { $0.key == "protein" })?.goal, 140)
    }

    func testAcceptingCoachTaskCreatesCalendarLinkedToDoBeforeClass() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiOnboardingState(isComplete: true, calendarConnected: true))
        try context.save()
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let classStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let provider = FakeCoachCalendar(events: [CalendarEventSummary(title: "Class", start: classStart, end: classStart.addingTimeInterval(3_600))])
        let suggestion = KoiCoachSuggestion(message: "A 3-mile run tomorrow before class would build consistency.", action: KoiCoachAction(type: .addTodo, title: "3-mile run", dueDate: "2023-10-04T07:00:00", why: "Before class."))
        let model = HubViewModel(publishesWidgetSnapshot: false, coachProvider: FixedCoachProvider(suggestion: suggestion))
        model.refresh(using: context)
        await model.requestCoach(event: "meal", using: provider)
        await model.acceptCoach(using: provider)

        let task = try XCTUnwrap(context.fetch(FetchDescriptor<KoiTask>()).first)
        let savedDueDate = try XCTUnwrap(task.dueAt)
        XCTAssertEqual(task.title, "3-mile run")
        XCTAssertEqual(savedDueDate, calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow))
        XCTAssertNotEqual(savedDueDate, classStart.addingTimeInterval(-1_800))
        XCTAssertLessThanOrEqual(savedDueDate.addingTimeInterval(30 * 60), classStart)
        XCTAssertTrue(task.hasTime)
        XCTAssertEqual(task.calendarEventID, "event-id")
    }

    func testOfflineCoachFallsBackToTrainingProteinRule() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = HubViewModel(publishesWidgetSnapshot: false, coachProvider: OfflineCoachProvider())
        model.refresh(using: context)

        await model.requestCoach(event: "workout", using: FakeCoachCalendar())

        XCTAssertEqual(model.coachSuggestion?.action.type, .adjustGoal)
        XCTAssertEqual(model.coachSuggestion?.action.nutrient, "protein")
        XCTAssertEqual(model.coachSuggestion?.action.delta, 10)
    }
}

private struct FixedCoachProvider: KoiCoaching {
    let suggestion: KoiCoachSuggestion
    func suggest(context: KoiCoachContext) async throws -> KoiCoachSuggestion { suggestion }
}

private struct OfflineCoachProvider: KoiCoaching {
    func suggest(context: KoiCoachContext) async throws -> KoiCoachSuggestion { throw EstimateClientError.connection }
}

private actor PhotoOnlyFoodEstimator: FoodEstimating {
    let value: FoodEstimateValue
    private var photo: Data?

    init(value: FoodEstimateValue) { self.value = value }

    func estimate(text: String?, jpegData: Data?) async throws -> FoodEstimateValue {
        photo = jpegData
        return value
    }

    func receivedPhoto() -> Data? { photo }
}

@MainActor
private final class FakeCoachCalendar: CalendarProviding {
    private let availableEvents: [CalendarEventSummary]
    init(events: [CalendarEventSummary] = []) { availableEvents = events }
    var isAvailable: Bool { true }
    func requestAccess() async throws {}
    func saveTaskEvent(_ task: CalendarTaskValue) async throws -> String { "event-id" }
    func deleteTaskEvent(identifier: String) async throws {}
    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary] { availableEvents }
}
