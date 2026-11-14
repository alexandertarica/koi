import Foundation
import Observation
import OSLog
import SwiftUI
import SwiftData
import KoiShared
import OSLog

enum TodoMode: String, CaseIterable, Identifiable {
    case list = "List"
    case matrix = "Matrix"
    var id: String { rawValue }
}

enum TodoSection: Int, CaseIterable, Identifiable {
    case urgentImportant = 0
    case notUrgentImportant = 1
    case urgentNotImportant = 2
    case someday = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .urgentImportant: "Do now"
        case .notUrgentImportant: "Plan it"
        case .urgentNotImportant: "Quick one"
        case .someday: "Someday"
        }
    }
    var hint: String {
        switch self {
        case .urgentImportant: "Urgent · Important"
        case .notUrgentImportant: "Important"
        case .urgentNotImportant: "Urgent"
        case .someday: "Neither"
        }
    }
    var quadrant: Int { rawValue }
}

struct TodoDraft {
    var title = ""
    var notes = ""
    var dueAt: Date?
    var hasTime = false
    var ignoredParsedDate = false
    var quadrant: TodoSection = .urgentImportant
    var hasChosenQuadrant = false
    var important: Bool { quadrant == .urgentImportant || quadrant == .notUrgentImportant }
}

struct HabitDraft {
    var title = ""
    var note = ""
    var schedule = "daily"
    var weekdays: Set<Int> = []
    var reminderHour: Int?
    var reminderMinute = 0
    var usesExactReminderTime = false
    var minimumVersion = ""
    var stackingCue = ""
    var identity = ""
}

@MainActor
@Observable
final class TodoViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "ToDo")
    private let calendar: Calendar
    private var context: ModelContext?
    private var calendarProvider: (any CalendarProviding)?
    private var notificationProvider: (any NotificationProviding)?
    private var calendarConnected = false
    private var remindersConnected = false
    private var notificationMode: KoiNotificationMode = .smart
    private var dailyCheckInHour = 9
    private var movementDays: [KoiMovementDay] = []
    private var movementGoal: KoiMovementGoal?
    private var nutrientEntries: [KoiNutrientEntry] = []
    private var foodEntries: [KoiFoodEntry] = []
    private var nutrientGoals: [KoiNutrientGoal] = []
    private(set) var tasks: [KoiTask] = []
    private(set) var habits: [KoiHabit] = []
    private(set) var logs: [KoiHabitLog] = []
    private(set) var mode: TodoMode = .list
    private(set) var showingArchive = false
    private(set) var selectedTaskID: UUID?
    private(set) var selectedHabitID: UUID?
    private(set) var showingNewTask = false
    private(set) var showingNewHabit = false
    private(set) var editingTaskID: UUID?
    private(set) var editingHabitID: UUID?
    private(set) var staleTaskID: UUID?
    private(set) var toast: String?
    private(set) var toastTaskID: UUID?
    private(set) var parsedTitleDate: ParsedDate?
    private(set) var tasksMarkedUrgent: Set<UUID> = []
    private(set) var coachHabit: KoiHabit?
    private(set) var coachAction: HabitCoachAction?
    var errorMessage: String?
    var taskDraft = TodoDraft()
    var habitDraft = HabitDraft()

    init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    var activeHabits: [KoiHabit] { habits.filter { $0.isActive && $0.pausedAt == nil } }
    var pausedHabits: [KoiHabit] { habits.filter { !$0.isActive || $0.pausedAt != nil } }
    var visibleTasks: [KoiTask] { showingArchive ? archivedTasks : activeTasks }
    var pendingTasks: [KoiTask] { activeTasks.filter { !$0.isComplete } }
    var finishedTasks: [KoiTask] { tasks.filter { $0.isComplete && !isArchived($0) } }
    var archivedTasks: [KoiTask] { tasks.filter { isArchived($0) } }
    var activeTasks: [KoiTask] { tasks.filter { !isArchived($0) } }
    var canSaveTask: Bool { taskDraft.hasChosenQuadrant && !taskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canSaveHabit: Bool {
        !habitDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (habitDraft.schedule != "someDays" || !habitDraft.weekdays.isEmpty)
    }
    var autoUrgentMessage: String? { toast }
    var shouldShowCoach: Bool {
        calendar.component(.weekday, from: .now) == 1 && (UserDefaults.standard.object(forKey: "koi.habitCoach.dismissedUntil") as? Date ?? .distantPast) <= .now && coachAction != nil
    }

    func load(_ context: ModelContext, calendarProvider: (any CalendarProviding)? = nil, notificationProvider: (any NotificationProviding)? = nil) {
        self.context = context
        if let calendarProvider { self.calendarProvider = calendarProvider }
        if let notificationProvider { self.notificationProvider = notificationProvider }
        do {
            tasks = try context.fetch(FetchDescriptor<KoiTask>(sortBy: [SortDescriptor(\.createdAt)]))
            habits = try context.fetch(FetchDescriptor<KoiHabit>(sortBy: [SortDescriptor(\.createdAt)]))
            logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
            movementDays = try context.fetch(FetchDescriptor<KoiMovementDay>())
            movementGoal = try context.fetch(FetchDescriptor<KoiMovementGoal>()).first
            nutrientEntries = try context.fetch(FetchDescriptor<KoiNutrientEntry>())
            foodEntries = try context.fetch(FetchDescriptor<KoiFoodEntry>())
            nutrientGoals = try context.fetch(FetchDescriptor<KoiNutrientGoal>())
            let settings = try context.fetch(FetchDescriptor<KoiOnboardingState>()).first
            calendarConnected = settings?.calendarConnected ?? false
            remindersConnected = settings?.remindersConnected ?? false
            notificationMode = KoiNotificationMode(rawValue: settings?.notificationMode ?? "smart") ?? .smart
            dailyCheckInHour = settings?.dailyCheckInHour ?? 9
            var changed = false
            for task in tasks where !task.isComplete && !isArchived(task) {
                if applyAutoUrgency(for: task) { changed = true }
            }
            if changed { try context.save() }
            refreshHabitCoach()
            checkSomedayTasks()
            Task { await synchronizeCalendarEvents() }
            Task { await synchronizeNotifications() }
        } catch { logger.error("Unable to load To-Do data.") }
    }

    func setMode(_ mode: TodoMode) { self.mode = mode }
    func toggleArchive() { showingArchive.toggle(); selectedTaskID = nil; selectedHabitID = nil }
    func openTask(_ task: KoiTask) { selectedTaskID = selectedTaskID == task.id ? nil : task.id; selectedHabitID = nil }
    func openHabit(_ habit: KoiHabit) { selectedHabitID = selectedHabitID == habit.id ? nil : habit.id; selectedTaskID = nil }
    func beginTask() { editingTaskID = nil; taskDraft = TodoDraft(); parsedTitleDate = nil; showingNewTask = true }
    func beginEditingTask(_ task: KoiTask) {
        editingTaskID = task.id
        let taskTime = task.dueAt.map { calendar.dateComponents([.hour, .minute], from: $0) }
        let hasTime = task.hasTime || (taskTime.map { ($0.hour ?? 0) != 0 || ($0.minute ?? 0) != 0 } ?? false)
        taskDraft = TodoDraft(title: task.title, notes: task.notes, dueAt: task.dueAt, hasTime: hasTime, ignoredParsedDate: false, quadrant: currentSection(for: task), hasChosenQuadrant: true)
        parsedTitleDate = nil
        showingNewTask = true
    }
    func beginHabit() { editingHabitID = nil; habitDraft = HabitDraft(); showingNewHabit = true }
    func beginEditingHabit(_ habit: KoiHabit) {
        editingHabitID = habit.id
        var draft = HabitDraft()
        draft.title = habit.title
        draft.note = habit.note
        draft.schedule = habit.schedule
        draft.weekdays = Set(habit.weekdays)
        if let time = habit.reminderTime {
            draft.reminderHour = calendar.component(.hour, from: time)
            draft.reminderMinute = calendar.component(.minute, from: time)
            draft.usesExactReminderTime = true
        }
        draft.minimumVersion = habit.minimumVersion
        draft.stackingCue = habit.stackingCue
        draft.identity = habit.identity
        habitDraft = draft
        showingNewHabit = true
    }
    func cancelNewTask() { showingNewTask = false; editingTaskID = nil; taskDraft = TodoDraft(); parsedTitleDate = nil }
    func cancelNewHabit() { showingNewHabit = false; editingHabitID = nil; habitDraft = HabitDraft() }

    func updateTaskTitle(_ title: String) {
        let hadParsedDate = parsedTitleDate != nil
        let manualDateWasChosen = taskDraft.ignoredParsedDate && taskDraft.dueAt != nil
        taskDraft.title = title
        let parsed = DateParsing.parse(title, relativeTo: .now, calendar: calendar)
        parsedTitleDate = parsed
        if let parsed {
            taskDraft.ignoredParsedDate = false
            taskDraft.dueAt = parsed.date
            taskDraft.hasTime = parsed.matchedText.contains("at ")
        } else {
            if hadParsedDate {
                taskDraft.dueAt = nil
                taskDraft.hasTime = false
            }
            taskDraft.ignoredParsedDate = manualDateWasChosen
        }
    }

    func ignoreParsedDate() {
        guard parsedTitleDate != nil else { return }
        taskDraft.ignoredParsedDate = true
        taskDraft.dueAt = nil
        parsedTitleDate = nil
    }

    func chooseTaskQuadrant(_ section: TodoSection) { taskDraft.quadrant = section; taskDraft.hasChosenQuadrant = true }
    func chooseTaskDate(_ date: Date?) {
        taskDraft.dueAt = date
        taskDraft.hasTime = date != nil && taskDraft.hasTime
        taskDraft.ignoredParsedDate = true
        parsedTitleDate = nil
    }
    func setTaskHasTime(_ value: Bool) { taskDraft.hasTime = value }
    func toggleTaskImportance(_ task: KoiTask, important: Bool) {
        task.important = important
        task.quadrant = quadrant(urgent: isUrgent(task), important: important)
        task.lastTouchedAt = .now
        persist()
    }
    func setDueDate(_ task: KoiTask, date: Date?) {
        task.dueAt = date
        if let date, daysUntil(date) <= 1, task.urgentOverride != false { task.urgentOverride = nil; _ = applyAutoUrgency(for: task) }
        task.lastTouchedAt = .now
        persist()
    }
    func undoAutoUrgent(_ task: KoiTask) {
        task.urgentOverride = false
        task.quadrant = quadrant(urgent: false, important: task.important)
        tasksMarkedUrgent.remove(task.id)
        toast = nil
        toastTaskID = nil
        persist()
    }

    func dismissAutoUrgent() { toast = nil; toastTaskID = nil }

    @discardableResult
    func saveTask() -> Bool {
        guard let context, canSaveTask else { return false }
        let title = taskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingTaskID, let task = tasks.first(where: { $0.id == editingTaskID }) {
            task.title = title
            task.notes = taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.dueAt = taskDraft.dueAt
            task.quadrant = taskDraft.quadrant.quadrant
            task.important = taskDraft.important
            task.lastTouchedAt = .now
            task.hasTime = taskDraft.hasTime
            _ = applyAutoUrgency(for: task)
            persist()
            showingNewTask = false
            self.editingTaskID = nil
            taskDraft = TodoDraft()
            return true
        }
        let task = KoiTask(title: title, notes: taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines), dueAt: taskDraft.dueAt, quadrant: taskDraft.quadrant.quadrant, important: taskDraft.important, hasTime: taskDraft.hasTime)
        task.lastTouchedAt = .now
        context.insert(task)
        do {
            try context.save()
            tasks.append(task)
            showingNewTask = false
            taskDraft = TodoDraft()
            parsedTitleDate = nil
            _ = applyAutoUrgency(for: task)
            persist()
            return true
        } catch { logger.error("Unable to save a to-do."); errorMessage = "Couldn't save this to-do. Try again."; return false }
    }

    @discardableResult
    func saveHabit() -> Bool {
        guard let context, canSaveHabit else { return false }
        let reminder: Date? = habitDraft.reminderHour.flatMap { hour in
            calendar.date(from: DateComponents(hour: hour, minute: habitDraft.reminderMinute))
        }
        let title = habitDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = habitDraft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let weekdays = habitDraft.schedule == "someDays" ? habitDraft.weekdays.sorted() : []
        let minimum = habitDraft.minimumVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let cue = habitDraft.stackingCue.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = habitDraft.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingHabitID, let habit = habits.first(where: { $0.id == editingHabitID }) {
            habit.title = title
            habit.note = note
            habit.schedule = habitDraft.schedule
            habit.weekdays = weekdays
            habit.reminderTime = reminder
            habit.minimumVersion = minimum
            habit.stackingCue = cue
            habit.identity = identity
            persist()
            showingNewHabit = false
            self.editingHabitID = nil
            habitDraft = HabitDraft()
            return true
        }
        let habit = KoiHabit(title: title, note: note, schedule: habitDraft.schedule, weekdays: weekdays, reminderTime: reminder, minimumVersion: minimum, stackingCue: cue, identity: identity)
        context.insert(habit)
        do {
            try context.save()
            habits.append(habit)
            showingNewHabit = false
            habitDraft = HabitDraft()
            return true
        } catch { logger.error("Unable to save a habit."); errorMessage = "Couldn't save this habit. Try again."; return false }
    }

    func toggleCompletion(_ task: KoiTask) {
        task.isComplete.toggle()
        task.completedAt = task.isComplete ? .now : nil
        task.lastTouchedAt = .now
        persist()
        Task { await synchronizeCalendarEvents() }
    }

    func toggleHabit(_ habit: KoiHabit, minimum: Bool = false) {
        guard let context else { return }
        let today = calendar.startOfDay(for: .now)
        if let log = logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: today) }) {
            log.completion = log.completion > 0 ? 0 : (minimum ? 1 : 2)
        } else {
            let log = KoiHabitLog(habitID: habit.id, date: today, completion: minimum ? 1 : 2)
            context.insert(log)
            logs.append(log)
        }
        persist()
    }

    func deleteTask(_ task: KoiTask) {
        guard let context else { return }
        if let eventID = task.calendarEventID, let calendarProvider {
            Task { try? await calendarProvider.deleteTaskEvent(identifier: eventID) }
        }
        if let reminderID = task.reminderID, let calendarProvider {
            Task { try? await calendarProvider.deleteTaskReminder(identifier: reminderID) }
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { context.delete(task); tasks.removeAll { $0.id == task.id } }
        persist()
    }

    func move(_ task: KoiTask, to section: TodoSection) {
        task.quadrant = section.quadrant
        task.important = section == .urgentImportant || section == .notUrgentImportant
        if task.urgentOverride == false && (section == .urgentImportant || section == .urgentNotImportant) { task.urgentOverride = true }
        else if section == .notUrgentImportant || section == .someday { task.urgentOverride = false }
        task.lastTouchedAt = .now
        persist()
    }

    func archiveTask(_ task: KoiTask) { task.archivedAt = .now; persist() }
    func restoreTask(_ task: KoiTask) { task.archivedAt = nil; task.completedAt = nil; task.isComplete = false; persist() }
    func pauseHabit(_ habit: KoiHabit) { habit.isActive = false; habit.pausedAt = .now; persist() }
    func restoreHabit(_ habit: KoiHabit) { habit.isActive = true; habit.pausedAt = nil; persist() }
    func deleteHabit(_ habit: KoiHabit) {
        guard let context else { return }
        for log in logs where log.habitID == habit.id { context.delete(log) }
        context.delete(habit)
        habits.removeAll { $0.id == habit.id }
        logs.removeAll { $0.habitID == habit.id }
        persist()
    }
    func reviewHabitCoach() {
        guard let action = coachAction else { return }
        switch action {
        case .graduate:
            guard let coachHabit else { return }
            coachHabit.graduatedAt = calendar.startOfDay(for: .now)
            persist()
        case .easeOff:
            guard let coachHabit else { return }
            beginEditingHabit(coachHabit)
            habitDraft.schedule = "weekly"
            habitDraft.weekdays = [calendar.component(.weekday, from: .now)]
        case .stepUp(_):
            guard let coachHabit else { return }
            beginEditingHabit(coachHabit)
            if habitDraft.minimumVersion.isEmpty { habitDraft.minimumVersion = "Current amount" }
        case .stack(let strongest):
            beginHabit()
            habitDraft.stackingCue = strongest
        }
    }
    func dismissHabitCoach() {
        UserDefaults.standard.set(calendar.date(byAdding: .day, value: 14, to: .now) ?? .now, forKey: "koi.habitCoach.dismissedUntil")
    }
    func dismissStaleTask(keep: Bool) {
        guard let id = staleTaskID, let task = tasks.first(where: { $0.id == id }) else { return }
        staleTaskID = nil
        if !keep { archiveTask(task) }
    }

    func count(in section: TodoSection) -> Int { pendingTasks.filter { currentSection(for: $0) == section }.count }
    func tasks(in section: TodoSection) -> [KoiTask] { pendingTasks.filter { currentSection(for: $0) == section }.sorted { $0.createdAt < $1.createdAt } }
    func currentSection(for task: KoiTask) -> TodoSection {
        let dueSoon = isUrgent(task)
        return TodoSection(rawValue: quadrant(urgent: dueSoon, important: task.important)) ?? .someday
    }
    func isUrgent(_ task: KoiTask) -> Bool {
        if task.urgentOverride == false { return false }
        return task.urgentOverride == true || (task.dueAt.map { daysUntil($0) <= 1 } ?? (task.quadrant == 0 || task.quadrant == 2))
    }
    func todayCompletion(for habit: KoiHabit) -> Int {
        if habit.graduatedAt.map({ calendar.startOfDay(for: $0) <= calendar.startOfDay(for: .now) }) == true { return 2 }
        return logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: .now) })?.completion ?? 0
    }
    func setReminderTime(hour: Int?, minute: Int = 0, exact: Bool = false) {
        habitDraft.reminderHour = hour
        habitDraft.reminderMinute = minute
        habitDraft.usesExactReminderTime = exact
    }
    func dueLabel(for task: KoiTask) -> String? {
        guard let dueAt = task.dueAt else { return nil }
        if calendar.isDateInToday(dueAt) {
            let time = calendar.dateComponents([.hour, .minute], from: dueAt)
            return time.hour == 0 && time.minute == 0 ? "Today" : "Today · \(dueAt.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(dueAt) { return "Tomorrow" }
        return dueAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func quadrant(urgent: Bool, important: Bool) -> Int {
        switch (urgent, important) { case (true,true): 0; case (false,true): 1; case (true,false): 2; case (false,false): 3 }
    }
    private func daysUntil(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? Int.max
    }
    @discardableResult
    private func applyAutoUrgency(for task: KoiTask) -> Bool {
        guard task.urgentOverride != false,
              let dueAt = task.dueAt,
              daysUntil(dueAt) <= 1,
              task.quadrant == TodoSection.notUrgentImportant.quadrant || task.quadrant == TodoSection.someday.quadrant else { return false }
        task.quadrant = quadrant(urgent: true, important: task.important)
        tasksMarkedUrgent.insert(task.id)
        showAutoUrgent(task)
        return true
    }
    private func showAutoUrgent(_ task: KoiTask) { toast = "Due soon · marked urgent"; toastTaskID = task.id; tasksMarkedUrgent.insert(task.id) }
    private func checkSomedayTasks() {
        guard staleTaskID == nil else { return }
        let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        staleTaskID = tasks.first(where: { !$0.isComplete && !isArchived($0) && currentSection(for: $0) == .someday && $0.lastTouchedAt < cutoff })?.id
    }

    private func refreshHabitCoach() {
        let today = calendar.startOfDay(for: .now)
        let active = habits.filter { $0.isActive && $0.pausedAt == nil && $0.graduatedAt == nil }
        guard !active.isEmpty else { coachHabit = nil; coachAction = nil; return }
        var inputs: [HabitCoachInput] = []
        var strongest: (habit: KoiHabit, completions: Int)?
        for habit in active {
            var scheduled = 0
            var complete = 0
            var minimum = 0
            for offset in 0..<66 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                      calendar.startOfDay(for: habit.createdAt) <= day,
                      coachIsScheduled(habit, on: day) else { continue }
                scheduled += 1
                let completion = logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: day) })?.completion ?? 0
                if completion == 2 { complete += 1 }
                if completion == 1 { minimum += 1 }
            }
            let strongWeeks = (1...4).allSatisfy { weekOffset in
                guard let date = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: today),
                      let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
                var weekScheduled = 0
                var weekComplete = 0
                for dayOffset in 0..<7 {
                    guard let day = calendar.date(byAdding: .day, value: dayOffset, to: interval.start),
                          day < interval.end, coachIsScheduled(habit, on: day) else { continue }
                    weekScheduled += 1
                    if logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: day) })?.completion == 2 { weekComplete += 1 }
                }
                return weekScheduled > 0 && weekComplete * 10 >= weekScheduled * 9
            }
            let weeklyCount = strongWeeks ? 4 : 0
            let activeDays = max((calendar.dateComponents([.day], from: calendar.startOfDay(for: habit.createdAt), to: today).day ?? 0) + 1, 0)
            inputs.append(HabitCoachInput(scheduledDays: scheduled, completedDays: complete, minimumDays: minimum, consecutiveStrongWeeks: weeklyCount, activeDays: activeDays, strongestHabitTitle: habit.title))
            if complete > (strongest?.completions ?? -1) { strongest = (habit, complete) }
        }
        guard let suggestion = HabitCoachEngine.suggestion(inputs) else { coachHabit = nil; coachAction = nil; return }
        coachHabit = suggestion.index < active.count ? active[suggestion.index] : nil
        coachAction = suggestion.index == active.count ? .stack(after: strongest?.habit.title ?? "your strongest habit") : suggestion.action
    }

    private func coachIsScheduled(_ habit: KoiHabit, on date: Date) -> Bool {
        switch habit.schedule {
        case "someDays": habit.weekdays.contains(calendar.component(.weekday, from: date))
        case "weekly": calendar.component(.weekday, from: habit.createdAt) == calendar.component(.weekday, from: date)
        case "monthly": calendar.component(.day, from: habit.createdAt) == calendar.component(.day, from: date)
        default: true
        }
    }
    private func persist() {
        guard let context else { return }
        do { try context.save(); load(context) }
        catch { logger.error("Unable to save To-Do changes."); errorMessage = "Couldn't save that change. Try again." }
    }

    private func synchronizeCalendarEvents() async {
        guard let calendarProvider else { return }
        for task in tasks {
            let shouldSync = !task.isComplete && task.archivedAt == nil && task.hasTime && task.dueAt != nil
            if calendarConnected, shouldSync, let start = task.dueAt {
                let value = CalendarTaskValue(id: task.id, title: task.title, notes: task.notes, start: start, durationMinutes: task.timeMinutes, eventIdentifier: task.calendarEventID)
                do {
                    task.calendarEventID = try await calendarProvider.saveTaskEvent(value)
                    try context?.save()
                } catch { logger.error("Unable to sync a timed to-do with Calendar.") }
            } else if let identifier = task.calendarEventID {
                do {
                    try await calendarProvider.deleteTaskEvent(identifier: identifier)
                    task.calendarEventID = nil
                    try context?.save()
                } catch { logger.error("Unable to remove a calendar event.") }
            }
            if remindersConnected, shouldSync, let dueAt = task.dueAt {
                do {
                    task.reminderID = try await calendarProvider.saveTaskReminder(ReminderTaskValue(id: task.id, title: task.title, notes: task.notes, dueAt: dueAt, reminderIdentifier: task.reminderID))
                    try context?.save()
                } catch { logger.error("Unable to sync a timed to-do with Apple Reminders.") }
            } else {
                if let identifier = task.reminderID {
                    do {
                        try await calendarProvider.deleteTaskReminder(identifier: identifier)
                        task.reminderID = nil
                        try context?.save()
                    } catch { logger.error("Unable to remove an Apple Reminder.") }
                }
            }
        }
    }

    private func synchronizeNotifications() async {
        guard let notificationProvider else { return }
        var reminders: [NotificationReminder] = []
        if notificationMode == .smart {
            reminders += NotificationPlanner.habitReminders(habits: habits, logs: logs, now: .now, calendar: calendar)
            for task in tasks where !task.isComplete && task.archivedAt == nil && task.hasTime && task.timeMinutes > 0 {
                guard let dueAt = task.dueAt else { continue }
                let reminderAt = dueAt.addingTimeInterval(-10 * 60)
                if reminderAt > .now {
                    reminders.append(NotificationReminder(id: "task-\(task.id.uuidString)", title: "In 10 minutes, \(task.title).", date: reminderAt, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "Coming up", tab: 1))
                }
            }
            reminders += smartNudges(now: .now)
        }
        do {
            try await notificationProvider.replaceScheduledReminders(Array(reminders.prefix(60)), dailyCheckInHour: notificationMode == .none ? nil : dailyCheckInHour)
        } catch { logger.error("Unable to refresh local reminders.") }
    }

    private func smartNudges(now: Date) -> [NotificationReminder] {
        let hour = calendar.component(.hour, from: now)
        guard (8...20).contains(hour) else { return [] }
        let today = calendar.startOfDay(for: now)
        let movement = movementDays.first { calendar.isDate($0.date, inSameDayAs: today) }
        let stepsGoal = max(movementGoal?.stepGoal ?? 8_000, 1)
        let stepsLeft = max(stepsGoal - (movement?.steps ?? 0), 0)
        let proteinGoal = nutrientGoals.first { $0.key == "protein" && $0.isActive }
        let proteinLogged = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: today) }.reduce(0) { $0 + $1.proteinGrams }
            + nutrientEntries.filter { $0.dayID == todayID(today) && $0.nutrientKey == "protein" }.reduce(0) { $0 + $1.value }
        let proteinLeft = max((proteinGoal?.goal ?? 0) - proteinLogged, 0)
        let dayID = todayID(today)
        let habitsToday = activeHabits.filter { habit in
            if habit.schedule == "daily" { return true }
            if habit.schedule == "someDays" { return habit.weekdays.contains(calendar.component(.weekday, from: today)) }
            return calendar.isDate(habit.createdAt, inSameDayAs: today)
        }.map { habit in
            let completion = logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: today) })?.completion ?? 0
            return HabitDayInput(isScheduled: true, completion: completion == 2 ? .complete : completion == 1 ? .minimum : .missed)
        }
        let habitScore = HabitRules.dayScore(habitsToday)
        let meals = foodEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: today) }.map { MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams) }
        let adjustments = nutrientEntries.filter { $0.dayID == dayID }.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
        let values = NutritionEngine.totals(meals: meals, adjustments: adjustments)
        let calorieGoal = nutrientGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200
        let nutrition = NutritionEngine.score(goals: nutrientGoals.filter(\.isActive).map { NutrientGoalInput(key: $0.key, goal: $0.goal, type: NutrientGoalType(rawValue: $0.goalType) ?? .track) }, values: values, calories: values["calories"] ?? 0, calorieGoal: calorieGoal, hasAnyIntake: NutritionEngine.hasAnyIntake(meals: meals, adjustments: adjustments)).score
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekMovement = movementDays.filter { $0.date >= weekStart && $0.date < weekEnd }
        let exercise = ExerciseEngine.score(ExerciseDayInput(steps: movement?.steps ?? 0, stepGoal: stepsGoal, isTrainingDay: movement?.isTrainingDay ?? false, workoutsInLastSevenDays: weekMovement.reduce(0) { $0 + $1.workoutCount }, weeklyWorkoutGoal: movementGoal?.weeklyWorkoutGoal ?? 4)).score
        let score = BalanceEngine.score(pillars: BalancePillars(habits: habitScore, nutrition: nutrition, exercise: exercise)).score
        guard score < 0.6 else { return [] }
        var result: [NotificationReminder] = []
        if hour < 15, let fire = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: now), fire > now,
           let weakest = [("Habits", habitScore), ("Nutrition", nutrition), ("Exercise", exercise)].min(by: { $0.1 < $1.1 }), weakest.1 < 0.5 {
            result.append(NotificationReminder(id: "nudge-catch-up", title: "A small step can lift today's \(weakest.0.lowercased()) balance.", date: fire, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "\(weakest.0) could use a moment", tab: tabFor(weakest.0), pillar: weakest.0))
        }
        if hour < 18, proteinLeft >= 15, let fire = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: now), fire > now {
            result.append(NotificationReminder(id: "nudge-protein", title: "\(Int(proteinLeft.rounded())) g left for today. Worth planning into dinner.", date: fire, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "Protein", tab: 3, pillar: "Nutrition"))
        }
        if hour < 19, stepsLeft > 0, stepsLeft <= 3_000, let fire = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now), fire > now {
            result.append(NotificationReminder(id: "nudge-steps", title: "About \(stepsLeft.formatted()) steps from your goal. A short walk finishes it.", date: fire, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "Nearly there", tab: 2, pillar: "Exercise"))
        }
        return result
    }

    private func todayID(_ date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    private func tabFor(_ pillar: String) -> Int {
        switch pillar { case "Habits": 1; case "Nutrition": 3; default: 2 }
    }

    private func isArchived(_ task: KoiTask) -> Bool {
        if task.archivedAt != nil { return true }
        guard task.isComplete, let completedAt = task.completedAt else { return false }
        return completedAt < (calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
    }
}
