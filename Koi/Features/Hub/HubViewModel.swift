import Foundation
import Observation
import OSLog
import SwiftData
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
    private var context: ModelContext?
    private var days: [KoiDay] = []
    private var habits: [KoiHabit] = []
    private var tasks: [KoiTask] = []
    private var logs: [KoiHabitLog] = []

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

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: .now)
    }

    var visibleItems: [HubTodayItem] {
        expandedItems ? items : Array(items.prefix(2))
    }

    var hiddenItemCount: Int { max(0, items.count - 2) }

    var greeting: String {
        let hour = calendar.component(.hour, from: .now)
        return switch hour {
        case 5..<12: "Good morning."
        case 12..<17: "Good afternoon."
        default: "Good evening."
        }
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
        let activeHabits = habits.filter { $0.isActive && calendar.startOfDay(for: $0.createdAt) <= selectedDate }
        let selectedLogs = logs.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        let habitDays = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HabitDayInput(isScheduled: true, completion: completion == 2 ? .complete : (completion == 1 ? .minimum : .missed))
        }
        let misses = activeHabits.map { habit in
            previousMisses(for: habit, before: selectedDate)
        }
        let habitScore = HabitRules.dayScore(habitDays, previousMisses: misses)
        balance = BalanceEngine.score(
            pillars: BalancePillars(
                habits: activeHabits.isEmpty ? (selectedDay?.habitsScore ?? 0) : habitScore,
                nutrition: selectedDay?.nutritionScore ?? 0,
                exercise: selectedDay?.exerciseScore ?? 0
            )
        )

        let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        let selectedHabits = activeHabits.map { habit in
            let completion = selectedLogs.first(where: { $0.habitID == habit.id })?.completion ?? 0
            return HubTodayItem(id: habit.id, title: habit.title, kind: .habit, completion: completion, dueAt: nil)
        }
        let selectedTasks = tasks.compactMap { task -> HubTodayItem? in
            guard let dueAt = task.dueAt, dueAt < dayEnd else { return nil }
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
    }

    private func previousMisses(for habit: KoiHabit, before date: Date) -> Int {
        var cursor = calendar.startOfDay(for: date)
        var misses = 0
        for _ in 0..<365 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor),
                  calendar.startOfDay(for: previousDay) >= calendar.startOfDay(for: habit.createdAt) else { break }
            let log = logs.first { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: previousDay) }
            guard (log?.completion ?? 0) == 0 else { break }
            misses += 1
            cursor = previousDay
        }
        return misses
    }

    private func updateTrend() {
        let today = calendar.startOfDay(for: .now)
        var week: [Double] = []
        var previous: [Double] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let score = days.first(where: { calendar.isDate($0.date, inSameDayAs: day) }).map {
                BalanceEngine.score(pillars: BalancePillars(habits: $0.habitsScore, nutrition: $0.nutritionScore, exercise: $0.exerciseScore)).score
            } ?? 0
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
}
