import Foundation
import Observation
import OSLog
import SwiftData
import WidgetKit
import KoiShared

struct HubTodayItem: Identifiable {
    enum Kind: Equatable {
        case habit
        case task
    }

    let id: UUID
    let title: String
    let kind: Kind
    let completion: Int
    let dueAt: Date?

    var isComplete: Bool { completion > 0 }
}

enum HubPillar: String, CaseIterable, Identifiable {
    case habits = "Habits"
    case nutrition = "Nutrition"
    case exercise = "Exercise"

    var id: String { rawValue }
    var tab: KoiTab {
        switch self {
        case .habits: .toDo
        case .nutrition: .intake
        case .exercise: .movement
        }
    }
}

extension Notification.Name {
    static let koiCoachRequested = Notification.Name("KoiCoachRequested")
}

enum DailyGoalAdjustment {
    static func delta(_ nutrient: String, on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Double {
        UserDefaults.standard.double(forKey: key("delta", nutrient, date, calendar))
    }

    static func add(_ amount: Double, to nutrient: String, on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        UserDefaults.standard.set(delta(nutrient, on: date, calendar: calendar) + amount, forKey: key("delta", nutrient, date, calendar))
    }

    static func adjustmentNote(on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String? {
        guard calendar.isDateInToday(date), delta("protein", on: date, calendar: calendar) != 0 else { return nil }
        return "Adjusted for today's workout"
    }

    static func holdBalance(_ score: Double, on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        guard calendar.isDateInToday(date) else { return }
        let key = key("floor", "balance", date, calendar)
        UserDefaults.standard.set(max(score, UserDefaults.standard.double(forKey: key)), forKey: key)
    }

    static func balanceFloor(on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Double {
        guard calendar.isDateInToday(date) else { return 0 }
        return UserDefaults.standard.double(forKey: key("floor", "balance", date, calendar))
    }

    static func clear(_ nutrient: String, on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        UserDefaults.standard.removeObject(forKey: key("delta", nutrient, date, calendar))
        UserDefaults.standard.removeObject(forKey: key("floor", "balance", date, calendar))
    }

    private static func key(_ kind: String, _ nutrient: String, _ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "koi.daily.\(kind).\(day).\(nutrient)"
    }
}

@MainActor
@Observable
final class HubViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Hub")
    private let calendar: Calendar
    private let publishesWidgetSnapshot: Bool
    private let coachProvider: any KoiCoaching
    private var context: ModelContext?
    private var days: [KoiDay] = []
    private var habits: [KoiHabit] = []
    private var tasks: [KoiTask] = []
    private var logs: [KoiHabitLog] = []
    private var foodEntries: [KoiFoodEntry] = []
    private var nutrientEntries: [KoiNutrientEntry] = []
    private var nutrientGoals: [KoiNutrientGoal] = []
    private var movementDays: [KoiMovementDay] = []
    private var movementGoal: KoiMovementGoal?
    private var profile: KoiProfile?

    private(set) var selectedDate: Date
    private(set) var balance = BalanceResult(score: 0, habits: 0, nutrition: 0, exercise: 0)
    private(set) var items: [HubTodayItem] = []
    private(set) var streak = StreakResult(current: 0, best: 0, freezes: 0)
    private(set) var trendText = "See progress"
    private(set) var trendIsPositive = true
    private(set) var hasWeekOfHistory = false
    private(set) var selectedDayOffset = 0
    private(set) var expandedItems = false
    private(set) var selectedItemID: UUID?
    private(set) var selectedPillar: HubPillar?
    private(set) var isScrubbing = false
    private var scrubStartOffset = 0
    private(set) var habitsDone = 0
    private(set) var habitsScheduled = 0
    private(set) var caloriesText = "0"
    private(set) var caloriesGoalText = "2,200"
    private(set) var proteinText = "0"
    private(set) var proteinGoalText = "140"
    private(set) var stepsText = "0"
    private(set) var stepGoalText = "8,000"
    private(set) var workoutsText = "0 of 4"
    private(set) var isProfileOpen = false
    private(set) var isProgressOpen = false
    private(set) var isPondOpen = false
    private(set) var coachSuggestion: KoiCoachSuggestion?
    private(set) var isCoachLoading = false
    private(set) var coachEvent: String?
    private var coachFirstEvent: CalendarEventSummary?

    init(calendar: Calendar = .autoupdatingCurrent, publishesWidgetSnapshot: Bool = true, coachProvider: any KoiCoaching = KoiCoachClient()) {
        self.calendar = calendar
        self.publishesWidgetSnapshot = publishesWidgetSnapshot
        self.coachProvider = coachProvider
        self.selectedDate = calendar.startOfDay(for: .now)
    }

    var visibleItems: [HubTodayItem] {
        expandedItems ? items : Array(items.prefix(2))
    }

    var hiddenItemCount: Int { max(0, items.count - 2) }

    var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        let salutation: String = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Still water"
        }
        return "\(salutation), \(profile?.name ?? "Friend")."
    }
    var displayName: String { profile?.name ?? "Friend" }

    func toggleProfile() { isProfileOpen.toggle(); isProgressOpen = false; isPondOpen = false }
    func toggleProgress() { isProgressOpen.toggle(); isProfileOpen = false; isPondOpen = false }
    func togglePond() { isPondOpen.toggle(); isProfileOpen = false; isProgressOpen = false }
    func closeInPlace() { isProfileOpen = false; isProgressOpen = false; isPondOpen = false }

    var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var formattedBalance: String { "\(Int((balance.score * 100).rounded()))%" }
    var focusWeights: BalanceWeights { selectedFocus.weights }

    func refresh(using modelContext: ModelContext) {
        context = modelContext
        do {
            days = try modelContext.fetch(FetchDescriptor<KoiDay>(sortBy: [SortDescriptor(\.date)]))
            habits = try modelContext.fetch(FetchDescriptor<KoiHabit>(sortBy: [SortDescriptor(\.createdAt)])).sorted { $0.createdAt < $1.createdAt }
            tasks = try modelContext.fetch(FetchDescriptor<KoiTask>(sortBy: [SortDescriptor(\.createdAt)]))
            logs = try modelContext.fetch(FetchDescriptor<KoiHabitLog>())
            foodEntries = try modelContext.fetch(FetchDescriptor<KoiFoodEntry>())
            nutrientEntries = try modelContext.fetch(FetchDescriptor<KoiNutrientEntry>())
            nutrientGoals = try modelContext.fetch(FetchDescriptor<KoiNutrientGoal>())
            movementDays = try modelContext.fetch(FetchDescriptor<KoiMovementDay>())
            movementGoal = try modelContext.fetch(FetchDescriptor<KoiMovementGoal>()).first
            profile = try modelContext.fetch(FetchDescriptor<KoiProfile>()).first
            updateDerivedState()
        } catch {
            logger.error("Unable to load Hub data.")
        }
    }

    func requestCoach(event: String, pondRank: String? = nil, using calendarProvider: any CalendarProviding) async {
        guard selectedDayOffset == 0, !isCoachLoading else { return }
        isCoachLoading = true
        coachEvent = event
        if let context {
            let now = calendar.startOfDay(for: .now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let firstEvent: CalendarEventSummary?
            let calendarConnected = (try? context.fetch(FetchDescriptor<KoiOnboardingState>()).first?.calendarConnected) ?? false
            if calendarConnected,
               let end = calendar.date(byAdding: .day, value: 1, to: tomorrow),
               let events = try? await calendarProvider.events(from: tomorrow, to: end) {
                firstEvent = events.first
            } else { firstEvent = nil }
            coachFirstEvent = firstEvent
            let totals = nutritionTotals(for: .now)
            let goals = Dictionary(uniqueKeysWithValues: nutrientGoals.filter(\.isActive).map { ($0.key, $0.goal + DailyGoalAdjustment.delta($0.key, on: .now, calendar: calendar)) })
            let contextValue = KoiCoachContext(
                event: event,
                today: Self.dayIdentifier(for: .now, calendar: calendar),
                timezone: calendar.timeZone.identifier,
                scores: ["habits": Int((balance.habits * 100).rounded()), "nutrition": Int((balance.nutrition * 100).rounded()), "exercise": Int((balance.exercise * 100).rounded())],
                goals: goals,
                totals: totals,
                pondRank: pondRank,
                firstCalendarEvent: firstEvent.map { "\($0.title) at \($0.start.formatted(date: .omitted, time: .shortened))" }
            )
            do {
                coachSuggestion = try await coachProvider.suggest(context: contextValue)
            } catch {
                coachSuggestion = Self.localCoach(event: event, protein: totals["protein"] ?? 0, proteinGoal: goals["protein"] ?? 140, firstEvent: firstEvent, pondRank: pondRank)
            }
        } else {
            coachSuggestion = Self.localCoach(event: event, protein: 0, proteinGoal: 140, firstEvent: nil, pondRank: pondRank)
        }
        isCoachLoading = false
    }

    func dismissCoach() { coachSuggestion = nil; coachEvent = nil; coachFirstEvent = nil }

    func acceptCoach(using calendarProvider: any CalendarProviding) async {
        guard let context, let action = coachSuggestion?.action else { dismissCoach(); return }
        switch action.type {
        case .none:
            dismissCoach()
        case .adjustGoal:
            let nutrient = action.nutrient ?? "protein"
            let delta = min(max(action.delta ?? 10, 1), 500)
            DailyGoalAdjustment.holdBalance(balance.score, on: .now, calendar: calendar)
            DailyGoalAdjustment.add(delta, to: nutrient, on: .now, calendar: calendar)
            dismissCoach()
            refresh(using: context)
        case .addTodo:
            guard let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { dismissCoach(); return }
            let dueDate = Self.planTomorrowSlot(firstEvent: coachFirstEvent, calendar: calendar)
            let task = KoiTask(title: title, notes: action.why, dueAt: dueDate, quadrant: 1, timeMinutes: 30, hasTime: true)
            context.insert(task)
            do {
                try context.save()
                let connected = (try? context.fetch(FetchDescriptor<KoiOnboardingState>()).first?.calendarConnected) ?? false
                if connected {
                    let value = CalendarTaskValue(id: task.id, title: task.title, notes: task.notes, start: dueDate, durationMinutes: task.timeMinutes, eventIdentifier: nil)
                    if let id = try? await calendarProvider.saveTaskEvent(value) { task.calendarEventID = id; try? context.save() }
                }
            } catch { logger.error("Unable to save a Coach task.") }
            dismissCoach()
            refresh(using: context)
        }
    }

    private static func localCoach(event: String, protein: Double, proteinGoal: Double, firstEvent: CalendarEventSummary?, pondRank: String?) -> KoiCoachSuggestion {
        if event == "workout", protein < proteinGoal {
            let message = pondRank.map { "You're \($0). A little more protein supports today's training." } ?? "Your workout could use a little more protein today."
            return KoiCoachSuggestion(message: message, action: KoiCoachAction(type: .adjustGoal, nutrient: "protein", delta: 10, why: "Support today's training."))
        }
        let beforeEvent: String
        if let firstEvent {
            let time = firstEvent.start.formatted(date: .omitted, time: .shortened)
            beforeEvent = " before your \(time) \(firstEvent.title.lowercased())"
        } else { beforeEvent = "" }
        let message = pondRank.map { "You're \($0). A 3-mile run tomorrow\(beforeEvent) would build consistency and help you move up." } ?? "A 3-mile run tomorrow\(beforeEvent) could round out your movement."
        let scheduled = planTomorrowSlot(firstEvent: firstEvent, calendar: .autoupdatingCurrent)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = .autoupdatingCurrent
        let iso = isoFormatter.string(from: scheduled)
        return KoiCoachSuggestion(message: message, action: KoiCoachAction(type: .addTodo, nutrient: nil, delta: nil, title: "3-mile run", dueDate: iso, why: firstEvent.map { "Scheduled before \($0.title)." } ?? "Make a little space for movement."))
    }

    static func planTomorrowSlot(firstEvent: CalendarEventSummary?, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let preferred = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        guard let event = firstEvent, calendar.isDate(event.start, inSameDayAs: tomorrow) else { return preferred }
        let duration: TimeInterval = 30 * 60
        if preferred < event.start, preferred.addingTimeInterval(duration) <= event.start { return preferred }
        return event.start.addingTimeInterval(-duration)
    }

    func selectDay(daysAgo: Int) {
        let offset = min(max(daysAgo, 0), 6)
        guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return }
        selectedDayOffset = offset
        selectedDate = date
        selectedItemID = nil
        selectedPillar = nil
        updateDerivedState()
    }

    func beginScrub() {
        isScrubbing = true
        scrubStartOffset = selectedDayOffset
    }

    func updateScrub(translation: CGFloat) {
        guard isScrubbing else { return }
        let steps = Int((translation / 34).rounded(.down))
        selectDay(daysAgo: scrubStartOffset + steps)
    }

    func endScrub() {
        isScrubbing = false
        selectDay(daysAgo: 0)
    }

    func toggleExpandedItems() {
        expandedItems.toggle()
    }

    func selectItem(_ id: UUID) {
        selectedItemID = selectedItemID == id ? nil : id
    }

    func selectPillar(_ pillar: HubPillar) {
        selectedPillar = selectedPillar == pillar ? nil : pillar
    }

    func toggle(_ item: HubTodayItem) {
        guard let context else { return }
        var didComplete = false
        switch item.kind {
        case .task:
            guard let task = tasks.first(where: { $0.id == item.id }) else { return }
            task.isComplete.toggle()
            task.completedAt = task.isComplete ? .now : nil
            task.lastTouchedAt = .now
            didComplete = task.isComplete
        case .habit:
            guard let habit = habits.first(where: { $0.id == item.id }) else { return }
            let log = logs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: selectedDate) }
            if let log {
                log.completion = log.completion > 0 ? 0 : 2
                didComplete = log.completion > 0
            } else {
                context.insert(KoiHabitLog(habitID: habit.id, date: selectedDate, completion: 2))
                didComplete = true
            }
        }
        do {
            try context.save()
            refresh(using: context)
            if didComplete { NotificationCenter.default.post(name: .koiCoachRequested, object: nil, userInfo: ["event": item.kind == .habit ? "habit" : "todo"]) }
        } catch {
            logger.error("Unable to save a Today update.")
        }
    }

    private func updateDerivedState() {
        let selectedDay = days.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        let activeHabits = habits.filter {
            $0.isActive && $0.pausedAt == nil && calendar.startOfDay(for: $0.createdAt) <= selectedDate && ($0.graduatedAt.map { selectedDate < calendar.startOfDay(for: $0) } ?? true) && isScheduled($0, on: selectedDate)
        }
        let selectedLogs = logs.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        let habitDays = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HabitDayInput(isScheduled: true, completion: completion == 2 ? .complete : (completion == 1 ? .minimum : .missed))
        }
        let misses = activeHabits.map { habit in
            previousMisses(for: habit, before: selectedDate)
        }
        let engineHabitScore = HabitRules.dayScore(habitDays, previousMisses: misses)
        habitsScheduled = activeHabits.count
        habitsDone = activeHabits.filter { habit in selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0 > 0 }.count
        let nutritionScore = nutritionScore(for: selectedDate) ?? selectedDay?.nutritionScore ?? 0
        let exerciseScore = exerciseScore(for: selectedDate) ?? selectedDay?.exerciseScore ?? 0
        let dailyTotals = nutritionTotals(for: selectedDate)
        caloriesText = Int(dailyTotals["calories"] ?? 0).formatted()
        proteinText = Int(dailyTotals["protein"] ?? 0).formatted()
        caloriesGoalText = Int((nutrientGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200) + DailyGoalAdjustment.delta("calories", on: selectedDate, calendar: calendar)).formatted()
        proteinGoalText = Int((nutrientGoals.first(where: { $0.key == "protein" })?.goal ?? 140) + DailyGoalAdjustment.delta("protein", on: selectedDate, calendar: calendar)).formatted()
        let movementForDay = movementDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        stepsText = (movementForDay?.steps ?? 0).formatted()
        stepGoalText = (movementGoal?.stepGoal ?? 8_000).formatted()
        let workouts = movementDays.filter { $0.date >= (calendar.date(byAdding: .day, value: -6, to: selectedDate) ?? selectedDate) && $0.date < (calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate) }.filter { $0.workoutCount > 0 }.count
        workoutsText = "\(workouts) of \(movementGoal?.weeklyWorkoutGoal ?? 4)"
        let liveBalance = BalanceEngine.score(
            pillars: BalancePillars(
                habits: activeHabits.isEmpty ? (selectedDay?.habitsScore ?? 0) : engineHabitScore,
                nutrition: nutritionScore,
                exercise: exerciseScore
            ), focus: selectedFocus
        )
        let rawBalance = ProcessInfo.processInfo.arguments.contains("-koiDemo") && profile?.name == "Maya" && calendar.isDateInToday(selectedDate)
            ? BalanceEngine.score(pillars: BalancePillars(habits: 0.75, nutrition: 0.64, exercise: 0.93), focus: selectedFocus)
            : liveBalance
        let floor = DailyGoalAdjustment.balanceFloor(on: selectedDate, calendar: calendar)
        balance = floor > rawBalance.score
            ? BalanceResult(score: floor, habits: rawBalance.habits, nutrition: rawBalance.nutrition, exercise: rawBalance.exercise)
            : rawBalance

        let selectedHabits = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HubTodayItem(id: habit.id, title: habit.title, kind: .habit, completion: completion, dueAt: nil)
        }
        let selectedTasks = tasks.compactMap { task -> HubTodayItem? in
            guard task.archivedAt == nil, !isArchived(task),
                  let dueAt = task.dueAt, calendar.isDate(dueAt, inSameDayAs: selectedDate) else { return nil }
            return HubTodayItem(id: task.id, title: task.title, kind: .task, completion: task.isComplete ? 2 : 0, dueAt: dueAt)
        }
        items = (selectedHabits + selectedTasks).sorted {
            if $0.isComplete != $1.isComplete { return !$0.isComplete }
            if $0.kind != $1.kind { return $0.kind == .habit }
            return ($0.dueAt ?? selectedDate) < ($1.dueAt ?? selectedDate)
        }

        var streakDays = days.map { BalanceDay(date: $0.date, score: $0.balance) }
        let today = calendar.startOfDay(for: .now)
        if calendar.isDate(selectedDate, inSameDayAs: today) {
            streakDays.removeAll { calendar.isDate($0.date, inSameDayAs: today) }
            streakDays.append(BalanceDay(date: today, score: balance.score))
        }
        let calculatedStreak = StreakEngine.calculate(
            days: streakDays,
            today: .now,
            calendar: calendar
        )
        streak = ProcessInfo.processInfo.arguments.contains("-koiDemo") && profile?.name == "Maya" && calendar.isDateInToday(selectedDate)
            ? StreakResult(current: 12, best: 18, freezes: 0)
            : calculatedStreak
        updateTrend()
        if publishesWidgetSnapshot, calendar.isDateInToday(selectedDate) {
            let parts = calendar.dateComponents([.year, .month, .day], from: selectedDate)
            let dayID = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            let habitItems = activeHabits.map { habit in
                KoiWidgetHabit(id: habit.id, title: habit.title, isComplete: (selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0) > 0)
            }
            KoiWidgetSnapshotStore.write(KoiWidgetSnapshot(
                day: dayID,
                balance: Int((balance.score * 100).rounded()),
                habits: Int((balance.habits * 100).rounded()),
                nutrition: Int((balance.nutrition * 100).rounded()),
                exercise: Int((balance.exercise * 100).rounded()),
                habitItems: habitItems,
                habitsCompleted: habitItems.filter(\.isComplete).count,
                habitsTotal: activeHabits.count
            ))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func previousMisses(for habit: KoiHabit, before date: Date) -> Int {
        var cursor = calendar.startOfDay(for: date)
        var misses = 0
        for _ in 0..<365 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor),
                  calendar.startOfDay(for: previousDay) >= calendar.startOfDay(for: habit.createdAt) else { break }
            guard isScheduled(habit, on: previousDay) else { cursor = previousDay; continue }
            let log = logs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: previousDay) }
            guard (log?.completion ?? 0) == 0 else { break }
            misses += 1
            cursor = previousDay
        }
        return misses
    }

    private func isScheduled(_ habit: KoiHabit, on date: Date) -> Bool {
        switch habit.schedule {
        case "weekly":
            return calendar.component(.weekday, from: date) == calendar.component(.weekday, from: habit.createdAt)
        case "monthly":
            let createdDay = calendar.component(.day, from: habit.createdAt)
            let lastDay = calendar.range(of: .day, in: .month, for: date)?.upperBound.advanced(by: -1) ?? createdDay
            return calendar.component(.day, from: date) == min(createdDay, lastDay)
        case "someDays":
            return habit.weekdays.contains(calendar.component(.weekday, from: date))
        default:
            return true
        }
    }

    private func isArchived(_ task: KoiTask) -> Bool {
        guard task.isComplete, let completedAt = task.completedAt else { return false }
        return completedAt < (calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
    }

    private func updateTrend() {
        if ProcessInfo.processInfo.arguments.contains("-koiDemo"), profile?.name == "Maya", calendar.isDateInToday(selectedDate) {
            hasWeekOfHistory = true
            trendIsPositive = false
            trendText = "17 vs last week"
            return
        }
        let today = calendar.startOfDay(for: .now)
        var week: [Double] = []
        var previous: [Double] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let snapshot = days.first(where: { calendar.isDate($0.date, inSameDayAs: day) })
            let nutrition = nutritionScore(for: day) ?? snapshot?.nutritionScore ?? 0
            let exercise = exerciseScore(for: day) ?? snapshot?.exerciseScore ?? 0
            let score = snapshot.map {
                BalanceEngine.score(pillars: BalancePillars(habits: $0.habitsScore, nutrition: nutrition, exercise: exercise), focus: selectedFocus).score
            } ?? (calendar.isDate(day, inSameDayAs: today) ? balance.score : 0)
            if offset < 7 { week.append(score) } else { previous.append(score) }
        }
        let historyStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        hasWeekOfHistory = Set(days.filter { $0.date >= historyStart }.map { calendar.startOfDay(for: $0.date) }).count >= 7
        guard hasWeekOfHistory, week.count == 7, previous.count == 7 else {
            trendText = "See progress"
            return
        }
        let currentTotal = week.reduce(0.0, +)
        let previousTotal = previous.reduce(0.0, +)
        let pointDifference = (currentTotal - previousTotal) / 7 * 100
        let difference = Int(pointDifference.rounded())
        if difference > 0 {
            trendIsPositive = true
            trendText = "\(difference) vs last week"
        } else if difference < 0 {
            trendIsPositive = false
            trendText = "\(abs(difference)) vs last week"
        } else {
            trendIsPositive = true
            trendText = "Even with last week"
        }
    }

    private var selectedFocus: BalanceFocus { BalanceFocus(rawValue: profile?.focusKey ?? "") ?? .allRounder }

    private func nutritionScore(for date: Date) -> Double? {
        let totals = nutritionTotals(for: date)
        let meals = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        let dayID = Self.dayIdentifier(for: date, calendar: calendar)
        let adjustments = nutrientEntries.filter { $0.dayID == dayID }.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
        guard NutritionEngine.hasAnyIntake(meals: meals.map { MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams) }, adjustments: adjustments) else { return nil }
        let calorieGoal = (nutrientGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200) + DailyGoalAdjustment.delta("calories", on: date, calendar: calendar)
        return NutritionEngine.score(
            goals: nutrientGoals.filter(\.isActive).map { NutrientGoalInput(key: $0.key, goal: $0.goal + DailyGoalAdjustment.delta($0.key, on: date, calendar: calendar), type: NutrientGoalType(rawValue: $0.goalType) ?? .track) },
            values: totals,
            calories: totals["calories"] ?? 0,
            calorieGoal: calorieGoal,
            hasAnyIntake: true
        ).score
    }

    private func nutritionTotals(for date: Date) -> [String: Double] {
        let meals = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }.map {
            MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams)
        }
        let dayID = Self.dayIdentifier(for: date, calendar: calendar)
        let adjustments = nutrientEntries.filter { $0.dayID == dayID }.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
        return NutritionEngine.totals(meals: meals, adjustments: adjustments)
    }

    private func exerciseScore(for date: Date) -> Double? {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date)) ?? date
        let days = movementDays.filter { $0.date >= start && $0.date < end }
        guard !days.isEmpty else { return nil }
        let currentDay = days.first { calendar.isDate($0.date, inSameDayAs: date) }
        let workoutCount = days.filter { $0.workoutCount > 0 }.count
        return ExerciseEngine.score(
            ExerciseDayInput(
                steps: currentDay?.steps ?? 0,
                stepGoal: movementGoal?.stepGoal ?? 8_000,
                isTrainingDay: (currentDay?.isTrainingDay ?? false) || (currentDay?.workoutCount ?? 0) > 0,
                workoutsInLastSevenDays: workoutCount,
                weeklyWorkoutGoal: movementGoal?.weeklyWorkoutGoal ?? 4
            )
        ).score
    }

    private static func dayIdentifier(for date: Date, calendar input: Calendar) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum PondUsernameStatus: Equatable {
    case idle, checking, available, taken, invalid
}

@MainActor
@Observable
final class PondViewModel {
    private let service: any PondService
    private let calendar: Calendar
    private(set) var snapshot: PondSnapshot?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var usernameStatus: PondUsernameStatus = .idle
    var username = ""
    var friendUsername = ""
    var pillars: Set<PondPillar> = Set(PondPillar.allCases)
    var endDate: Date
    var rule = ""

    init(service: any PondService, calendar: Calendar = .autoupdatingCurrent) {
        self.service = service
        self.calendar = calendar
        self.snapshot = service.cachedSnapshot
        self.endDate = PondEngine.nextThursday(calendar: calendar)
    }

    var needsUsername: Bool { snapshot == nil && service.currentUsername == nil }
    var hasFriends: Bool { (snapshot?.members.count ?? 0) > 1 }
    var isSprintFinished: Bool { snapshot?.sprint.map { $0.endDate <= .now } ?? false }
    var leaderboard: [PondLeaderboardEntry] { guard let snapshot else { return [] }; return PondEngine.leaderboard(for: snapshot, calendar: calendar) }
    var winner: PondLeaderboardEntry? { guard let snapshot else { return nil }; return PondEngine.winner(for: snapshot, calendar: calendar) }
    var currentRank: Int? { leaderboard.first(where: { $0.member.username.lowercased() == snapshot?.currentUsername.lowercased() })?.rank }
    var rankSummary: String? {
        guard let rank = currentRank, let count = snapshot?.members.count, count > 1 else { return nil }
        let suffix: String
        switch rank % 100 {
        case 11...13: suffix = "th"
        default:
            switch rank % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(rank)\(suffix) of \(count) in your pond"
    }

    func load(displayName: String, scores: BalanceResult) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let loaded = try await service.load() { snapshot = loaded }
            else { snapshot = service.cachedSnapshot }
            errorMessage = nil
            announceWinIfNeeded()
            await syncDailyScore(scores)
        } catch {
            snapshot = service.cachedSnapshot ?? snapshot
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Your pond couldn't load. Try again."
        }
    }

    func retry(displayName: String, scores: BalanceResult) async { await load(displayName: displayName, scores: scores) }

    func checkUsername(_ value: String) async {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PondEngine.isValidUsername(clean) else { usernameStatus = clean.isEmpty ? .idle : .invalid; return }
        usernameStatus = .checking
        do {
            let available = try await service.usernameIsAvailable(clean)
            guard username.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(clean) == .orderedSame else { return }
            usernameStatus = available ? .available : .taken
            errorMessage = nil
        } catch {
            guard username.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(clean) == .orderedSame else { return }
            usernameStatus = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription
        }
    }

    func createProfile(displayName: String) async {
        guard usernameStatus == .available else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            snapshot = try await service.createProfile(username: username, displayName: displayName)
            errorMessage = nil
            KoiHaptics.success()
        } catch { setError(error) }
    }

    func addFriend() async {
        let name = friendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            snapshot = try await service.addFriend(username: name)
            friendUsername = ""
            errorMessage = nil
            KoiHaptics.check()
        } catch { setError(error) }
    }

    func toggle(_ pillar: PondPillar) {
        if pillars.contains(pillar) { if pillars.count > 1 { pillars.remove(pillar) } }
        else { pillars.insert(pillar) }
        KoiHaptics.change()
    }

    func startSprint() async {
        guard !pillars.isEmpty, endDate > .now else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            snapshot = try await service.startSprint(pillars: pillars, endDate: endDate, rule: rule)
            errorMessage = nil
            KoiHaptics.success()
        } catch { setError(error) }
    }

    func syncDailyScore(_ scores: BalanceResult) async {
        guard let username = service.currentUsername ?? snapshot?.currentUsername else { return }
        let value = PondDailyScore(username: username, date: .now, habits: scores.habits, nutrition: scores.nutrition, exercise: scores.exercise, calendar: calendar)
        do {
            try await service.upsertDailyScore(value)
            if let cached = service.cachedSnapshot { snapshot = cached }
            announceWinIfNeeded()
        }
        catch {
            if let cached = service.cachedSnapshot { snapshot = cached }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Your pond couldn't sync. Try again."
        }
    }

    private func setError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Your pond couldn't update. Try again."
    }

    private func announceWinIfNeeded() {
        guard let snapshot, let sprint = snapshot.sprint, PondEngine.winner(for: snapshot, calendar: calendar) != nil else { return }
        let key = "koi.pond.announcedWin.\(sprint.recordName)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        KoiHaptics.success()
    }
}
