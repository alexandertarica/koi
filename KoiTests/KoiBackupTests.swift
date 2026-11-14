import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiBackupTests: XCTestCase {
    func testIntentActionsPersistWaterProteinMealAndWorkout() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try KoiIntentStore.addNutrient("water", amount: 12, context: context)
        try KoiIntentStore.addNutrient("water", amount: 8, context: context)
        try KoiIntentStore.addNutrient("protein", amount: 24, context: context)
        try KoiIntentStore.addMeal(name: "Lunch", calories: 540, protein: 32, context: context)
        try KoiIntentStore.logWorkout(name: "Strength", minutes: 45, context: context)

        let nutrients = try context.fetch(FetchDescriptor<KoiNutrientEntry>())
        XCTAssertEqual(nutrients.first(where: { $0.nutrientKey == "water" })?.value, 20)
        XCTAssertEqual(nutrients.first(where: { $0.nutrientKey == "protein" })?.value, 24)
        let meals = try context.fetch(FetchDescriptor<KoiFoodEntry>())
        XCTAssertEqual(meals.first?.name, "Lunch")
        XCTAssertEqual(meals.first?.calories, 540)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiWorkoutSession>()).first?.isComplete, true)
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiWorkoutSet>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiMovementDay>()).first?.didManuallyTrain, true)
    }

    func testCompleteHabitIntentMatchesAndChecksOffAnActiveHabit() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = KoiHabit(title: "Take a walk")
        context.insert(habit)
        XCTAssertTrue(try KoiIntentStore.completeHabit(named: "Take a walk", context: context))
        XCTAssertFalse(try KoiIntentStore.completeHabit(named: "Read", context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiHabitLog>()).first?.completion, 2)
    }

    func testIntentActionsRejectInvalidNutritionInputs() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        XCTAssertThrowsError(try KoiIntentStore.addNutrient("water", amount: -1, context: context))
        XCTAssertThrowsError(try KoiIntentStore.addNutrient("water", amount: 129, context: context))
        XCTAssertThrowsError(try KoiIntentStore.addMeal(name: "", calories: 200, protein: 10, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiNutrientEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<KoiFoodEntry>()).isEmpty)
    }

    func testArchiveRoundTripRestoresCompleteUserSchemaAndReplacesLocalData() throws {
        let source = try KoiSchema.makeContainer(inMemory: true)
        let sourceContext = ModelContext(source)
        let day = Calendar.current.startOfDay(for: .now)
        let profile = KoiProfile(name: "Sam", joinedAt: day, focusKey: "mover", avatarJPEG: Data([1, 2, 3]))
        let onboarding = KoiOnboardingState(isComplete: true, hasSeenTour: true, birthYear: 1991, heightCM: 170, sexAtBirth: "Female", healthConnected: true, calendarConnected: true, notificationMode: "onceDaily", dailyCheckInHour: 7, backupEnabled: true, lastBackupAt: day)
        let habit = KoiHabit(title: "Read", createdAt: day, schedule: "someDays", weekdays: [2, 4], reminderTime: day, minimumVersion: "One page", stackingCue: "After tea", identity: "Reader")
        habit.pausedAt = day
        habit.graduatedAt = day
        let task = KoiTask(title: "Call", notes: "After lunch", dueAt: day.addingTimeInterval(50_000), quadrant: 2, createdAt: day, urgentOverride: false, timeMinutes: 45, hasTime: true)
        task.calendarEventID = "event-1"
        task.reminderID = "reminder-1"
        onboarding.remindersConnected = true
        task.completedAt = day
        task.archivedAt = day
        let food = KoiFoodEntry(name: "Lunch", loggedAt: day, calories: 500, proteinGrams: 40, imageJPEG: Data([9]), notes: "Saved")
        let routine = KoiWorkoutRoutine(name: "Upper", plannedAt: day)
        let session = KoiWorkoutSession(name: "Strength", routineID: routine.id, startedAt: day)
        let lift = KoiWorkoutLift(sessionID: session.id, name: "Bench")
        let cardio = KoiCardioSession(activity: "Run", detail: "Outdoor", startedAt: day, durationSeconds: 1200, distanceMeters: 3_000)
        cardio.routeData = Data([4, 5])

        sourceContext.insert(profile)
        sourceContext.insert(onboarding)
        sourceContext.insert(KoiBodyWeightEntry(date: day, weightLB: 150))
        sourceContext.insert(KoiDay(date: day, balance: 0.8, habitsScore: 0.5, nutritionScore: 0.9, exerciseScore: 1))
        sourceContext.insert(habit)
        sourceContext.insert(KoiHabitLog(habitID: habit.id, date: day, completion: 1))
        sourceContext.insert(task)
        sourceContext.insert(food)
        sourceContext.insert(KoiQuickNote(text: "A quiet morning, then a short walk.", action: "reflection", createdAt: day))
        sourceContext.insert(KoiNutrientGoal(key: "protein", name: "Protein", unit: "g", goal: 140, step: 5))
        sourceContext.insert(KoiNutrientEntry(date: day, nutrientKey: "protein", value: 12))
        let supplement = KoiSupplement(name: "Vitamin D")
        sourceContext.insert(supplement)
        sourceContext.insert(KoiSupplementLog(supplementID: supplement.id, date: day, isTaken: true))
        sourceContext.insert(KoiMovementGoal(stepGoal: 9_000, weeklyWorkoutGoal: 5, healthEnabled: true))
        sourceContext.insert(KoiMovementDay(date: day, healthSteps: 7_500, manualStepAdjustment: 200, healthWorkoutCount: 1, didManuallyTrain: true))
        sourceContext.insert(routine)
        sourceContext.insert(KoiRoutineLift(routineID: routine.id, name: "Press"))
        sourceContext.insert(session)
        sourceContext.insert(lift)
        sourceContext.insert(KoiWorkoutSet(sessionID: session.id, liftID: lift.id, loggedAt: day, weightLB: 135, reps: 8, isWarmUp: true))
        sourceContext.insert(cardio)
        try sourceContext.save()

        let archiveData = try JSONEncoder().encode(KoiBackupArchive.capture(sourceContext, createdAt: day))
        let archive = try JSONDecoder().decode(KoiBackupArchive.self, from: archiveData)
        XCTAssertEqual(archive.rows.count, 21)
        let destination = try KoiSchema.makeContainer(inMemory: true)
        let destinationContext = ModelContext(destination)
        destinationContext.insert(KoiHabit(title: "Local-only"))
        try destinationContext.save()
        try archive.restore(into: destinationContext)

        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Sam")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiOnboardingState>()).first?.dailyCheckInHour, 7)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiOnboardingState>()).first?.remindersConnected, true)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).first?.weekdays, [2, 4])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).first?.pausedAt, day)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).first?.graduatedAt, day)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiTask>()).first?.calendarEventID, "event-1")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiTask>()).first?.reminderID, "reminder-1")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiTask>()).first?.hasTime, true)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiFoodEntry>()).first?.imageJPEG, Data([9]))
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiQuickNote>()).first?.text, "A quiet morning, then a short walk.")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiMovementDay>()).first?.steps, 7_700)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiWorkoutLift>()).first?.sessionID, session.id)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiCardioSession>()).first?.routeData, Data([4, 5]))
        XCTAssertFalse(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).contains(where: { $0.title == "Local-only" }))
        XCTAssertEqual(archive.createdAt, day)
    }
}
