import Foundation
import Observation
import OSLog
import SwiftUI
import SwiftData
import KoiShared

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

    func load(_ context: ModelContext) {
        self.context = context
        do {
            tasks = try context.fetch(FetchDescriptor<KoiTask>(sortBy: [SortDescriptor(\.createdAt)]))
            habits = try context.fetch(FetchDescriptor<KoiHabit>(sortBy: [SortDescriptor(\.createdAt)]))
            logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
            var changed = false
            for task in tasks where !task.isComplete && !isArchived(task) {
                if applyAutoUrgency(for: task) { changed = true }
            }
            if changed { try context.save() }
            checkSomedayTasks()
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
        let hasTime = taskTime.map { ($0.hour ?? 0) != 0 || ($0.minute ?? 0) != 0 } ?? false
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

    func saveTask() {
        guard let context, canSaveTask else { return }
        let title = taskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingTaskID, let task = tasks.first(where: { $0.id == editingTaskID }) {
            task.title = title
            task.notes = taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.dueAt = taskDraft.dueAt
            task.quadrant = taskDraft.quadrant.quadrant
            task.important = taskDraft.important
            task.lastTouchedAt = .now
            _ = applyAutoUrgency(for: task)
            persist()
            showingNewTask = false
            self.editingTaskID = nil
            taskDraft = TodoDraft()
            return
        }
        let task = KoiTask(title: title, notes: taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines), dueAt: taskDraft.dueAt, quadrant: taskDraft.quadrant.quadrant, important: taskDraft.important)
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
        } catch { logger.error("Unable to save a to-do."); errorMessage = "Couldn't save this to-do. Try again." }
    }

    func saveHabit() {
        guard let context, canSaveHabit else { return }
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
            return
        }
        let habit = KoiHabit(title: title, note: note, schedule: habitDraft.schedule, weekdays: weekdays, reminderTime: reminder, minimumVersion: minimum, stackingCue: cue, identity: identity)
        context.insert(habit)
        do {
            try context.save()
            habits.append(habit)
            showingNewHabit = false
            habitDraft = HabitDraft()
        } catch { logger.error("Unable to save a habit."); errorMessage = "Couldn't save this habit. Try again." }
    }

    func toggleCompletion(_ task: KoiTask) {
        task.isComplete.toggle()
        task.completedAt = task.isComplete ? .now : nil
        task.lastTouchedAt = .now
        persist()
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
        logs.first(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: .now) })?.completion ?? 0
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
    private func persist() {
        guard let context else { return }
        do { try context.save(); load(context) }
        catch { logger.error("Unable to save To-Do changes."); errorMessage = "Couldn't save that change. Try again." }
    }

    private func isArchived(_ task: KoiTask) -> Bool {
        if task.archivedAt != nil { return true }
        guard task.isComplete, let completedAt = task.completedAt else { return false }
        return completedAt < (calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
    }
}
