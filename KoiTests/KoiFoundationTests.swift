import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiFoundationTests: XCTestCase {
    func testInMemoryContainerCanPersistCoreModels() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let day = KoiDay(date: .now, balance: 0.72)
        context.insert(day)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KoiDay>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.balance, 0.72)
    }

    func testInMemoryContainerCanPersistAHabitCheckIn() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = KoiHabit(title: "Read")
        let log = KoiHabitLog(habitID: habit.id, completion: 2)
        context.insert(habit)
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KoiHabitLog>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.habitID, habit.id)
        XCTAssertEqual(fetched.first?.completion, 2)
    }

    func testWidgetSnapshotRoundTripsAndClampsPillarValues() throws {
        let habit = KoiWidgetHabit(id: UUID(), title: "Walk outside", isComplete: true)
        let snapshot = KoiWidgetSnapshot(day: "2026-11-14", balance: 112, habits: -4, nutrition: 62, exercise: 75, habitItems: [habit])
        let decoded = try JSONDecoder().decode(KoiWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.balance, 100)
        XCTAssertEqual(decoded.habits, 0)
        XCTAssertEqual(decoded.nutrition, 62)
        XCTAssertEqual(decoded.habitItems, [habit])
        XCTAssertEqual(decoded.habitsCompleted, 1)
        XCTAssertEqual(decoded.habitsTotal, 1)
    }

    func testCoachResponseDecodesStructuredActionAndSchedule() throws {
        let json = Data(#"{"message":"A short run could help.","action":{"type":"addTodo","title":"3-mile run","dueDate":"2026-11-15T07:00:00-08:00","why":"Before class."}}"#.utf8)
        let result = try JSONDecoder().decode(KoiCoachSuggestion.self, from: json)

        XCTAssertEqual(result.action.type, .addTodo)
        XCTAssertEqual(result.action.title, "3-mile run")
        XCTAssertEqual(result.action.dueDate, "2026-11-15T07:00:00-08:00")
        XCTAssertEqual(result.action.why, "Before class.")
    }

    func testCoachContextIncludesLocalISODateAndTimeZone() throws {
        let context = KoiCoachContext(
            event: "meal",
            today: "2026-11-14",
            timezone: "America/Los_Angeles",
            scores: ["habits": 60, "nutrition": 40, "exercise": 20],
            goals: ["protein": 140],
            totals: ["protein": 30],
            pondRank: "3rd of 5",
            firstCalendarEvent: "Class at 9:00 AM"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])

        XCTAssertEqual(object["today"] as? String, "2026-11-14")
        XCTAssertEqual(object["timezone"] as? String, "America/Los_Angeles")
        XCTAssertNil(object["date"])
    }

    func testDemoSeedBuildsAFullWeekAndLeavesExistingDataAlone() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try KoiDemoSeeder.seedIfEmpty(context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Maya")
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<KoiHabit>()).map(\.title)), Set(["Morning walk", "Stretch", "Read 10 pages", "Plan tomorrow", "Long training session"]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiHabitLog>()).count, 145)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiFoodEntry>()).count, 32)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiDay>()).count, 33)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<KoiTask>()).map(\.title)), Set(["Finish project draft", "Grocery run", "Book dentist", "Call trainer"]))

        try KoiDemoSeeder.seedIfEmpty(context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiFoodEntry>()).count, 32)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiWorkoutSession>()).count, 3)
    }

    func testDemoHubHasScoredNutritionAndAContinuousWeekStreak() throws {
        DailyGoalAdjustment.clear("protein")
        defer { DailyGoalAdjustment.clear("protein") }
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try KoiDemoSeeder.seedIfEmpty(context)

        let model = HubViewModel(calendar: .current, publishesWidgetSnapshot: false)
        model.refresh(using: context)

        XCTAssertEqual(model.balance.habits, 0.875, accuracy: 0.001)
        XCTAssertEqual(model.balance.nutrition, 0.6351, accuracy: 0.001)
        XCTAssertEqual(model.balance.exercise, 0.9275, accuracy: 0.001)
        XCTAssertEqual(model.balance.score, 0.81, accuracy: 0.01)
        XCTAssertEqual(model.streak.current, 12)
        XCTAssertEqual(model.streak.best, 18)
        XCTAssertEqual(model.stepsText, "6,840")
        XCTAssertEqual(model.stepGoalText, "8,000")
        XCTAssertEqual(model.caloriesText, "1,450")
        XCTAssertEqual(model.proteinText, "92")
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiNutrientEntry>()).first(where: { $0.nutrientKey == "added_sugar" })?.value, 22)
    }

    func testDemoSeedDoesNotRunWhenAnySavedModelExists() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiTask(title: "Keep this task"))
        try context.save()

        try KoiDemoSeeder.seedIfEmpty(context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiTask>()).map(\.title), ["Keep this task"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiProfile>()).isEmpty)
    }

    func testStageSeedUsesLiveScoresAndOneCompletedHabit() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try KoiDemoSeeder.seedForStageLaunch(context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Jasmine")
        let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
        let habits = try context.fetch(FetchDescriptor<KoiHabit>())
        let logs = try context.fetch(FetchDescriptor<KoiHabitLog>()).filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(logs.filter { $0.completion > 0 }.count, 1)
        XCTAssertEqual(logs.first(where: { $0.habitID == habits.first(where: { $0.title == "Morning walk" })?.id })?.completion, 2)
        let breakfast = try XCTUnwrap(context.fetch(FetchDescriptor<KoiFoodEntry>()).first(where: { $0.name == "Light breakfast" }))
        XCTAssertEqual(breakfast.calories, 420)
        XCTAssertEqual(breakfast.proteinGrams, 20)
        XCTAssertFalse(try context.fetch(FetchDescriptor<KoiMovementDay>()).first(where: { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: today) })?.isTrainingDay ?? true)

        let model = HubViewModel(calendar: .current, publishesWidgetSnapshot: false)
        model.refresh(using: context)
        XCTAssertTrue((0.45...0.55).contains(model.balance.score), "Starting stage Balance was \(model.balance.score), pillars: \(model.balance.habits), \(model.balance.nutrition), \(model.balance.exercise), weights: \(model.focusWeights)")
        XCTAssertTrue((0.20...0.30).contains(model.balance.exercise), "Starting stage Exercise was \(model.balance.exercise)")
        XCTAssertGreaterThan(model.streak.current, 0)
        XCTAssertTrue(model.hasWeekOfHistory)

        let startScore = model.balance.score
        XCTAssertEqual(startScore, 0.4819, accuracy: 0.01)
        let todayMovement = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiMovementDay>()).first(where: { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: today) }))
        todayMovement.didManuallyTrain = true
        try context.save()
        model.refresh(using: context)
        let workoutScore = model.balance.score
        XCTAssertEqual(workoutScore, 0.6069, accuracy: 0.01)
        XCTAssertTrue((0.12...0.20).contains(workoutScore - startScore), "Workout should visibly raise Balance by 12–20 points")

        context.insert(KoiFoodEntry(name: "Protein bar", calories: 150, proteinGrams: 28, carbohydrateGrams: 18, fatGrams: 5, fiberGrams: 3, addedSugarGrams: 4, sodiumMilligrams: 160))
        try context.save()
        model.refresh(using: context)
        let proteinBarScore = model.balance.score
        XCTAssertEqual(proteinBarScore, 0.6679, accuracy: 0.01)
        XCTAssertGreaterThan(proteinBarScore, workoutScore, "The protein bar should raise Balance after the workout")
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiNutrientGoal>()).first(where: { $0.key == "protein" })?.goal, 75)

        DailyGoalAdjustment.add(10, to: "protein")
        defer { DailyGoalAdjustment.clear("protein", on: today) }
        let intake = IntakeViewModel()
        intake.load(context)
        XCTAssertEqual(intake.nutrientRows.first(where: { $0.key == "protein" })?.goal, 85)
    }

    func testDemoLaunchReplacesStoredContentWithTheFixedSample() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(KoiProfile(name: "Existing"))
        context.insert(KoiTask(title: "Personal task"))
        try context.save()

        try KoiDemoSeeder.seedForDemoLaunch(context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Maya")
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<KoiTask>()).map(\.title)), Set(["Finish project draft", "Grocery run", "Book dentist", "Call trainer"]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiSupplement>()).map(\.name).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).count, 3)
    }
}
