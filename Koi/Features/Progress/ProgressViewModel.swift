import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

enum ProgressScope: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

struct ProgressDayMetric: Identifiable, Equatable {
    let date: Date
    let balance: Double
    let habits: Double
    let nutrition: Double
    let exercise: Double
    let scheduledHabits: Int
    let completedHabits: Int
    let workoutCount: Int
    var id: Date { date }
    var dayNumber: Int { Calendar.current.component(.day, from: date) }
}

struct ProgressPeriodSummary: Equatable {
    let days: Int
    let averageBalance: Double
    let habitsDone: Int
    let habitsScheduled: Int
    let trainingDays: Int
    let nutritionAverage: Double
}

struct ProgressWeek: Identifiable {
    let index: Int
    let days: [ProgressDayMetric?]
    let average: Double?
    var id: Int { index }
}

@MainActor
@Observable
final class ProgressViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Progress")
    private let calendar: Calendar
    private var context: ModelContext?
    private var habits: [KoiHabit] = []
    private var habitLogs: [KoiHabitLog] = []
    private var foodEntries: [KoiFoodEntry] = []
    private var nutrientEntries: [KoiNutrientEntry] = []
    private var nutrientGoals: [KoiNutrientGoal] = []
    private var movementDays: [KoiMovementDay] = []
    private var movementGoal: KoiMovementGoal?
    private var workoutSessions: [KoiWorkoutSession] = []
    private var cardioSessions: [KoiCardioSession] = []
    private var focus = BalanceFocus.allRounder

    private(set) var scope: ProgressScope = .month
    private(set) var focusedDate: Date?
    private(set) var monthMetrics: [ProgressDayMetric] = []
    private(set) var weekMetrics: [ProgressDayMetric] = []
    private(set) var currentSummary = ProgressPeriodSummary(days: 0, averageBalance: 0, habitsDone: 0, habitsScheduled: 0, trainingDays: 0, nutritionAverage: 0)
    private(set) var previousSummary = ProgressPeriodSummary(days: 0, averageBalance: 0, habitsDone: 0, habitsScheduled: 0, trainingDays: 0, nutritionAverage: 0)
    private(set) var errorMessage: String?

    init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    var monthLabel: String { calendar.monthSymbols[safe: calendar.component(.month, from: .now) - 1] ?? "Month" }
    var focusLabel: String { focusTitle(focus) }
    var weeklyWorkoutGoal: Int { movementGoal?.weeklyWorkoutGoal ?? 4 }
    var workoutGoalTarget: Int {
        guard focusedDate == nil, scope == .month else { return weeklyWorkoutGoal }
        return max(Int(ceil(Double(currentSummary.days) / 7 * Double(weeklyWorkoutGoal))), weeklyWorkoutGoal)
    }
    var weekdayLabels: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return ["S", "M", "T", "W", "T", "F", "S"] }
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % symbols.count] }
    }
    var scopeTitle: String {
        if let focusedDate { return focusedDate.formatted(.dateTime.month(.wide).day()) }
        return scope == .week ? "THIS WEEK" : "THIS MONTH"
    }
    var previousTitle: String {
        if let focusedDate { return calendar.date(byAdding: .day, value: -1, to: focusedDate)?.formatted(.dateTime.month(.abbreviated).day()).uppercased() ?? "PREVIOUS DAY" }
        return scope == .week ? "LAST WEEK" : "LAST MONTH · TO DATE"
    }
    var monthWeeks: [ProgressWeek] {
        guard let first = monthMetrics.first else { return [] }
        let leading = max(calendar.component(.weekday, from: first.date) - calendar.firstWeekday, 0) % 7
        let cells: [ProgressDayMetric?] = Array(repeating: nil, count: leading) + monthMetrics.map(Optional.some)
        return stride(from: 0, to: cells.count, by: 7).enumerated().map { index, offset in
            let chunk = Array(cells[offset..<min(offset + 7, cells.count)])
            let metrics = chunk.compactMap { $0 }
            let padded = chunk + Array(repeating: nil, count: max(0, 7 - chunk.count))
            let average = metrics.isEmpty ? nil : metrics.map(\.balance).reduce(0, +) / Double(metrics.count)
            return ProgressWeek(index: index, days: padded, average: average)
        }
    }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            habits = try context.fetch(FetchDescriptor<KoiHabit>())
            habitLogs = try context.fetch(FetchDescriptor<KoiHabitLog>())
            foodEntries = try context.fetch(FetchDescriptor<KoiFoodEntry>())
            nutrientEntries = try context.fetch(FetchDescriptor<KoiNutrientEntry>())
            nutrientGoals = try context.fetch(FetchDescriptor<KoiNutrientGoal>())
            movementDays = try context.fetch(FetchDescriptor<KoiMovementDay>())
            movementGoal = try context.fetch(FetchDescriptor<KoiMovementGoal>()).first
            workoutSessions = try context.fetch(FetchDescriptor<KoiWorkoutSession>())
            cardioSessions = try context.fetch(FetchDescriptor<KoiCardioSession>())
            focus = BalanceFocus(rawValue: try context.fetch(FetchDescriptor<KoiProfile>()).first?.focusKey ?? "") ?? .allRounder
            update()
        } catch {
            logger.error("Unable to load Progress data.")
            errorMessage = "Couldn't load your progress. Try again."
        }
    }

    func setScope(_ value: ProgressScope) {
        scope = value
        focusedDate = nil
        update()
    }

    func select(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        focusedDate = calendar.isDate(focusedDate ?? .distantPast, inSameDayAs: normalized) ? nil : normalized
        update()
    }

    func clearError() { errorMessage = nil }

    private func update() {
        let today = calendar.startOfDay(for: .now)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        monthMetrics = (0..<(calendar.range(of: .day, in: .month, for: today)?.count ?? 30)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart), date <= today else { return nil }
            return metric(for: date)
        }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        weekMetrics = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart), date <= today else { return nil }
            return metric(for: date)
        }

        if let focusedDate {
            let current = metric(for: focusedDate)
            let previous = metric(for: calendar.date(byAdding: .day, value: -1, to: focusedDate) ?? focusedDate)
            currentSummary = summary([current])
            previousSummary = summary([previous])
            return
        }

        let currentStart = scope == .week ? weekStart : monthStart
        let daysSoFar = max(calendar.dateComponents([.day], from: currentStart, to: today).day ?? 0, 0) + 1
        let current = (0..<daysSoFar).compactMap { calendar.date(byAdding: .day, value: $0, to: currentStart).map(metric(for:)) }
        let previousStart = scope == .week
            ? (calendar.date(byAdding: .day, value: -7, to: currentStart) ?? currentStart)
            : (calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart)
        let previous = (0..<daysSoFar).compactMap { calendar.date(byAdding: .day, value: $0, to: previousStart).map(metric(for:)) }
        currentSummary = summary(current)
        previousSummary = summary(previous)
    }

    private func metric(for date: Date) -> ProgressDayMetric {
        let day = calendar.startOfDay(for: date)
        let scheduled = habits.filter { habit in
            habit.isActive && habit.pausedAt == nil && calendar.startOfDay(for: habit.createdAt) <= day && (habit.graduatedAt.map { day < calendar.startOfDay(for: $0) } ?? true) && isScheduled(habit, on: day)
        }
        let scheduledInputs = scheduled.map { habit -> HabitDayInput in
            let log = habitLogs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: day) }
            let completion = log?.completion ?? 0
            return HabitDayInput(isScheduled: true, completion: completion == 2 ? .complete : (completion == 1 ? .minimum : .missed))
        }
        let misses = scheduled.map { previousMisses(for: $0, before: day) }
        let habitScore = HabitRules.dayScore(scheduledInputs, previousMisses: misses)
        let completedHabitCount = scheduled.filter { habit in habitLogs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: day) }?.completion ?? 0 > 0 }.count
        let meals = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }.map {
            MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams)
        }
        let dayID = dayIdentifier(day)
        let adjustments = nutrientEntries.filter { $0.dayID == dayID }.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
        let nutritionGoals = nutrientGoals.isEmpty ? Self.defaultNutritionGoals : nutrientGoals.map { NutrientGoalInput(key: $0.key, goal: $0.goal, type: NutrientGoalType(rawValue: $0.goalType) ?? .track) }
        let totals = NutritionEngine.totals(meals: meals, adjustments: adjustments)
        let calories = totals["calories"] ?? 0
        let caloriesGoal = nutrientGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200
        let nutrition = NutritionEngine.score(goals: nutritionGoals, values: totals, calories: calories, calorieGoal: caloriesGoal, hasAnyIntake: NutritionEngine.hasAnyIntake(meals: meals, adjustments: adjustments)).score
        let dayMovement = movementDays.first { calendar.isDate($0.date, inSameDayAs: day) }
        let workoutEvents = completedWorkoutCount(through: day)
        let rollingWorkouts = (0..<7).reduce(0) { total, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { return total }
            return total + completedWorkoutCount(on: date)
        }
        let exercise = ExerciseEngine.score(ExerciseDayInput(steps: dayMovement?.steps ?? 0, stepGoal: movementGoal?.stepGoal ?? 8_000, isTrainingDay: (dayMovement?.isTrainingDay ?? false) || workoutEvents > 0, workoutsInLastSevenDays: rollingWorkouts, weeklyWorkoutGoal: movementGoal?.weeklyWorkoutGoal ?? 4)).score
        let balance = BalanceEngine.score(pillars: BalancePillars(habits: habitScore, nutrition: nutrition, exercise: exercise), focus: focus)
        return ProgressDayMetric(date: day, balance: balance.score, habits: habitScore, nutrition: nutrition, exercise: exercise, scheduledHabits: scheduled.count, completedHabits: completedHabitCount, workoutCount: workoutEvents)
    }

    private func summary(_ metrics: [ProgressDayMetric]) -> ProgressPeriodSummary {
        let count = metrics.count
        return ProgressPeriodSummary(
            days: count,
            averageBalance: count == 0 ? 0 : metrics.map(\.balance).reduce(0, +) / Double(count),
            habitsDone: metrics.reduce(0) { $0 + $1.completedHabits },
            habitsScheduled: metrics.reduce(0) { $0 + $1.scheduledHabits },
            trainingDays: metrics.reduce(0) { $0 + $1.workoutCount },
            nutritionAverage: count == 0 ? 0 : metrics.map(\.nutrition).reduce(0, +) / Double(count)
        )
    }

    private func completedWorkoutCount(through day: Date) -> Int { completedWorkoutCount(on: day) }

    private func completedWorkoutCount(on date: Date) -> Int {
        let strength = workoutSessions.filter { $0.isComplete && calendar.isDate($0.startedAt, inSameDayAs: date) }.count
        let cardio = cardioSessions.filter { $0.isComplete && calendar.isDate($0.startedAt, inSameDayAs: date) }.count
        let health = movementDays.first { calendar.isDate($0.date, inSameDayAs: date) }?.healthWorkoutCount ?? 0
        let hasManual = movementDays.first { calendar.isDate($0.date, inSameDayAs: date) }?.didManuallyTrain ?? false
        return max(strength + cardio + health, hasManual && strength + cardio + health == 0 ? 1 : 0)
    }

    private func previousMisses(for habit: KoiHabit, before date: Date) -> Int {
        var cursor = calendar.startOfDay(for: date)
        var misses = 0
        for _ in 0..<365 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), calendar.startOfDay(for: previous) >= calendar.startOfDay(for: habit.createdAt) else { break }
            guard isScheduled(habit, on: previous) else { cursor = previous; continue }
            let log = habitLogs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: previous) }
            guard (log?.completion ?? 0) == 0 else { break }
            misses += 1
            cursor = previous
        }
        return misses
    }

    private func isScheduled(_ habit: KoiHabit, on date: Date) -> Bool {
        switch habit.schedule {
        case "weekly": return calendar.component(.weekday, from: date) == calendar.component(.weekday, from: habit.createdAt)
        case "monthly":
            let created = calendar.component(.day, from: habit.createdAt)
            let last = calendar.range(of: .day, in: .month, for: date)?.upperBound.advanced(by: -1) ?? created
            return calendar.component(.day, from: date) == min(created, last)
        case "someDays": return habit.weekdays.contains(calendar.component(.weekday, from: date))
        default: return true
        }
    }

    private func dayIdentifier(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func focusTitle(_ focus: BalanceFocus) -> String {
        switch focus {
        case .allRounder: "The All-Rounder"
        case .ritualist: "The Ritualist"
        case .nourisher: "The Nourisher"
        case .mover: "The Mover"
        }
    }

    private static let defaultNutritionGoals = [
        NutrientGoalInput(key: "calories", goal: 2_200, type: .around),
        NutrientGoalInput(key: "protein", goal: 140, type: .reach),
        NutrientGoalInput(key: "fiber", goal: 30, type: .reach),
        NutrientGoalInput(key: "water", goal: 100, type: .reach)
    ]
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
