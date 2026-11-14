import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiBackupTests: XCTestCase {
    func testArchiveRoundTripRestoresCompleteUserSchemaAndReplacesLocalData() throws {
        let source = try KoiSchema.makeContainer(inMemory: true)
        let sourceContext = ModelContext(source)
        let day = Calendar.current.startOfDay(for: .now)
        let profile = KoiProfile(name: "Sam", joinedAt: day, focusKey: "mover", avatarJPEG: Data([1, 2, 3]))
        let onboarding = KoiOnboardingState(isComplete: true, hasSeenTour: true, birthYear: 1991, heightCM: 170, sexAtBirth: "Female", healthConnected: true, calendarConnected: true, notificationMode: "onceDaily", dailyCheckInHour: 7, backupEnabled: true, lastBackupAt: day)
        let habit = KoiHabit(title: "Read", createdAt: day, schedule: "someDays", weekdays: [2, 4], reminderTime: day, minimumVersion: "One page", stackingCue: "After tea", identity: "Reader")
        habit.pausedAt = day
        let task = KoiTask(title: "Call", notes: "After lunch", dueAt: day.addingTimeInterval(50_000), quadrant: 2, createdAt: day, urgentOverride: false, timeMinutes: 45, hasTime: true)
        task.calendarEventID = "event-1"
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
        XCTAssertEqual(archive.rows.count, 20)
        let destination = try KoiSchema.makeContainer(inMemory: true)
        let destinationContext = ModelContext(destination)
        destinationContext.insert(KoiHabit(title: "Local-only"))
        try destinationContext.save()
        try archive.restore(into: destinationContext)

        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiProfile>()).first?.name, "Sam")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiOnboardingState>()).first?.dailyCheckInHour, 7)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).first?.weekdays, [2, 4])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).first?.pausedAt, day)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiTask>()).first?.calendarEventID, "event-1")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiTask>()).first?.hasTime, true)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiFoodEntry>()).first?.imageJPEG, Data([9]))
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiMovementDay>()).first?.steps, 7_700)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiWorkoutLift>()).first?.sessionID, session.id)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<KoiCardioSession>()).first?.routeData, Data([4, 5]))
        XCTAssertFalse(try destinationContext.fetch(FetchDescriptor<KoiHabit>()).contains(where: { $0.title == "Local-only" }))
        XCTAssertEqual(archive.createdAt, day)
    }
}
