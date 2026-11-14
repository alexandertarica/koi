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

@MainActor
@Observable
final class HubViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Hub")
    private let calendar: Calendar
    private let publishesWidgetSnapshot: Bool
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
    private(set) var hasWeekOfHistory = false
    private(set) var selectedDayOffset = 0
    private(set) var expandedItems = false
    private(set) var selectedItemID: UUID?
    private(set) var selectedPillar: HubPillar?
    var presentsProgress = false
    var presentsProfile = false

    init(calendar: Calendar = .autoupdatingCurrent, publishesWidgetSnapshot: Bool = true) {
        self.calendar = calendar
        self.publishesWidgetSnapshot = publishesWidgetSnapshot
        self.selectedDate = calendar.startOfDay(for: .now)
    }

    var visibleItems: [HubTodayItem] {
        expandedItems ? items : Array(items.prefix(2))
    }

    var hiddenItemCount: Int { max(0, items.count - 2) }

    var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        let salutation: String = switch hour {
        case 5..<12: "Good morning."
        case 12..<17: "Good afternoon."
        default: "Good evening."
        }
        let prefix = salutation.replacingOccurrences(of: ".", with: "")
        return "\(prefix), \(profile?.name ?? "Friend")."
    }

    var dateLabel: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var formattedBalance: String { "\(Int((balance.score * 100).rounded()))%" }

    func refresh(using modelContext: ModelContext) {
        context = modelContext
        do {
            days = try modelContext.fetch(FetchDescriptor<KoiDay>(sortBy: [SortDescriptor(\.date)]))
            habits = try modelContext.fetch(FetchDescriptor<KoiHabit>(sortBy: [SortDescriptor(\.createdAt)]))
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

    func selectDay(daysAgo: Int) {
        let offset = min(max(daysAgo, 0), 6)
        guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return }
        selectedDayOffset = offset
        selectedDate = date
        selectedItemID = nil
        selectedPillar = nil
        updateDerivedState()
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
        switch item.kind {
        case .task:
            guard let task = tasks.first(where: { $0.id == item.id }) else { return }
            task.isComplete.toggle()
            task.completedAt = task.isComplete ? .now : nil
            task.lastTouchedAt = .now
        case .habit:
            guard let habit = habits.first(where: { $0.id == item.id }) else { return }
            let log = logs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: selectedDate) }
            if let log {
                log.completion = log.completion > 0 ? 0 : 2
            } else {
                context.insert(KoiHabitLog(habitID: habit.id, date: selectedDate, completion: 2))
            }
        }
        do {
            try context.save()
            refresh(using: context)
        } catch {
            logger.error("Unable to save a Today update.")
        }
    }

    private func updateDerivedState() {
        let selectedDay = days.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        let activeHabits = habits.filter {
            $0.isActive && $0.pausedAt == nil && calendar.startOfDay(for: $0.createdAt) <= selectedDate && isScheduled($0, on: selectedDate)
        }
        let selectedLogs = logs.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        let habitDays = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HabitDayInput(isScheduled: true, completion: completion == 2 ? .complete : (completion == 1 ? .minimum : .missed))
        }
        let misses = activeHabits.map { habit in
            previousMisses(for: habit, before: selectedDate)
        }
        let habitScore = HabitRules.dayScore(habitDays, previousMisses: misses)
        let nutritionScore = nutritionScore(for: selectedDate) ?? selectedDay?.nutritionScore ?? 0
        let exerciseScore = exerciseScore(for: selectedDate) ?? selectedDay?.exerciseScore ?? 0
        balance = BalanceEngine.score(
            pillars: BalancePillars(
                habits: activeHabits.isEmpty ? (selectedDay?.habitsScore ?? 0) : habitScore,
                nutrition: nutritionScore,
                exercise: exerciseScore
            ), focus: selectedFocus
        )

        let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        let selectedHabits = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HubTodayItem(id: habit.id, title: habit.title, kind: .habit, completion: completion, dueAt: nil)
        }
        let selectedTasks = tasks.compactMap { task -> HubTodayItem? in
            guard task.archivedAt == nil, !isArchived(task), let dueAt = task.dueAt, dueAt < dayEnd else { return nil }
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
        streak = StreakEngine.calculate(
            days: streakDays,
            today: .now,
            calendar: calendar
        )
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
            trendText = "↗ \(difference) vs last week"
        } else if difference < 0 {
            trendText = "↘ \(abs(difference)) vs last week"
        } else {
            trendText = "Even with last week"
        }
    }

    private var selectedFocus: BalanceFocus { BalanceFocus(rawValue: profile?.focusKey ?? "") ?? .allRounder }

    private func nutritionScore(for date: Date) -> Double? {
        let meals = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }.map {
            MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams)
        }
        let dayID = Self.dayIdentifier(for: date, calendar: calendar)
        let adjustments = nutrientEntries.filter { $0.dayID == dayID }.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
        guard NutritionEngine.hasAnyIntake(meals: meals, adjustments: adjustments) else { return nil }
        let totals = NutritionEngine.totals(meals: meals, adjustments: adjustments)
        let calorieGoal = nutrientGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200
        return NutritionEngine.score(
            goals: nutrientGoals.filter(\.isActive).map { NutrientGoalInput(key: $0.key, goal: $0.goal, type: NutrientGoalType(rawValue: $0.goalType) ?? .track) },
            values: totals,
            calories: totals["calories"] ?? 0,
            calorieGoal: calorieGoal,
            hasAnyIntake: true
        ).score
    }

    private func exerciseScore(for date: Date) -> Double? {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date)) ?? date
        let days = movementDays.filter { $0.date >= start && $0.date < end }
        guard !days.isEmpty else { return nil }
        let currentDay = days.first { calendar.isDate($0.date, inSameDayAs: date) }
        let workoutCount = days.reduce(0) { $0 + $1.workoutCount }
        return ExerciseEngine.score(
            ExerciseDayInput(
                steps: currentDay?.steps ?? 0,
                stepGoal: movementGoal?.stepGoal ?? 8_000,
                isTrainingDay: currentDay?.isTrainingDay ?? false,
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
