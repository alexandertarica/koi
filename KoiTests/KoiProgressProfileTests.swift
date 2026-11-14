import XCTest
import SwiftData
import KoiShared
import UserNotifications
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

        let model = HubViewModel(publishesWidgetSnapshot: false)
        model.refresh(using: context)

        XCTAssertTrue(model.greeting.contains("Sam"))
        XCTAssertEqual(model.balance.score, 0.525, accuracy: 0.01)
    }

    func testNotificationPreferencesPersistAndScheduleDailyCheckIn() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = ProfileViewModel()
        model.load(context)
        let provider = FakeNotificationProvider()

        await model.setNotifications(.onceDaily, hour: 9, provider: provider)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first)
        XCTAssertEqual(state.notificationMode, KoiNotificationMode.onceDaily.rawValue)
        XCTAssertEqual(state.dailyCheckInHour, 9)
        XCTAssertNil(provider.lastCheckInHour)
        XCTAssertFalse(provider.lastReminders.isEmpty)
        XCTAssertTrue(provider.lastReminders.allSatisfy { Calendar.current.component(.hour, from: $0.date) == 9 })

        await model.setNotifications(.none, hour: 9, provider: provider)
        XCTAssertNil(provider.lastCheckInHour)
    }

    func testNotificationPlannerUsesQuietHoursAndSundayRecap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 10)) ?? .now
        let reminders = NotificationPlanner.checkIns(hour: 9, now: saturday, calendar: calendar)

        XCTAssertEqual(reminders.count, 7)
        XCTAssertEqual(reminders.first?.title, "A quiet moment to check in with your balance.")
        XCTAssertEqual(reminders[1].notificationTitle, "Your week")
        XCTAssertEqual(calendar.component(.weekday, from: reminders[1].date), 1)
        XCTAssertTrue(NotificationPlanner.checkIns(hour: 7, now: saturday, calendar: calendar).isEmpty)
        let morning = NotificationPlanner.morningContent(yesterdayScore: 0.735, suggestion: "A short walk could help.")
        XCTAssertEqual(morning.body, "Yesterday 74%. A short walk could help.")
        XCTAssertEqual(NotificationPlanner.recapContent(average: 0.68, bestDay: "Friday").body, "68% average, best day Friday. Tap to see it.")
    }

    func testHabitReminderIsOneShotAndSuppressedAfterCompletion() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 0)) ?? .now
        let reminderTime = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 10, minute: 0)) ?? .now
        let habit = KoiHabit(title: "Read", createdAt: now, reminderTime: reminderTime)

        let pending = NotificationPlanner.habitReminders(habits: [habit], logs: [], now: now, calendar: calendar)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].date, calendar.date(bySettingHour: 9, minute: 50, second: 0, of: now))
        XCTAssertFalse(pending[0].repeatsDaily)
        XCTAssertEqual(pending[0].tab, 1)

        let completed = KoiHabitLog(habitID: habit.id, date: now, completion: 1)
        XCTAssertTrue(NotificationPlanner.habitReminders(habits: [habit], logs: [completed], now: now, calendar: calendar).isEmpty)
    }

    func testCalendarConnectionPreferencePersistsAfterAuthorization() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = ProfileViewModel()
        model.load(context)
        await model.connectCalendar(using: FakeCalendarProvider())

        XCTAssertTrue(model.calendarConnected)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).calendarConnected)
    }

    func testAppleReminderSyncTracksTimedTasksAndDisconnects() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let due = Date.now.addingTimeInterval(3_600)
        let task = KoiTask(title: "Call the studio", dueAt: due, hasTime: true)
        context.insert(task)
        try context.save()
        let model = ProfileViewModel()
        model.load(context)
        let provider = FakeCalendarProvider()

        await model.setRemindersConnected(true, using: provider)

        XCTAssertTrue(model.remindersConnected)
        XCTAssertEqual(task.reminderID, "reminder-\(task.id.uuidString)")
        XCTAssertEqual(provider.savedReminders.count, 1)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiOnboardingState>()).first).remindersConnected)

        await model.setRemindersConnected(false, using: provider)

        XCTAssertFalse(model.remindersConnected)
        XCTAssertNil(task.reminderID)
        XCTAssertEqual(provider.deletedReminderIDs, ["reminder-\(task.id.uuidString)"])
    }
}

@MainActor
private final class FakeNotificationProvider: NotificationProviding {
    var status: UNAuthorizationStatus = .authorized
    var lastCheckInHour: Int?
    var lastReminders: [NotificationReminder] = []
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status = .authorized; return true }
    func replaceScheduledReminders(_ reminders: [NotificationReminder], dailyCheckInHour: Int?) async throws {
        lastReminders = reminders
        lastCheckInHour = dailyCheckInHour
    }
    func refreshPlan(using context: ModelContext) async {}
    func removeReminder(id: String) {}
}

@MainActor
private final class FakeCalendarProvider: CalendarProviding {
    var isAvailable = true
    var savedReminders: [ReminderTaskValue] = []
    var deletedReminderIDs: [String] = []
    func requestAccess() async throws {}
    func saveTaskEvent(_ task: CalendarTaskValue) async throws -> String { "event-\(task.id.uuidString)" }
    func deleteTaskEvent(identifier: String) async throws {}
    func requestReminderAccess() async throws {}
    func saveTaskReminder(_ task: ReminderTaskValue) async throws -> String { savedReminders.append(task); return "reminder-\(task.id.uuidString)" }
    func deleteTaskReminder(identifier: String) async throws { deletedReminderIDs.append(identifier) }
}
