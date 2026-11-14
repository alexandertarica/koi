import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiTodoTests: XCTestCase {
    func testTaskTitleParsesTomorrowAndAutoUrgencyCanBeUndone() throws {
        let context = try makeContext()
        let model = TodoViewModel()
        model.load(context)
        model.beginTask()
        model.updateTaskTitle("Call Sam tomorrow at 3pm")

        XCTAssertNotNil(model.parsedTitleDate)
        XCTAssertTrue(Calendar.current.isDateInTomorrow(model.taskDraft.dueAt ?? .distantPast))
        model.updateTaskTitle("Call Sam")
        XCTAssertNil(model.taskDraft.dueAt)
        model.updateTaskTitle("Call Sam tomorrow at 3pm")
        model.chooseTaskQuadrant(.notUrgentImportant)
        model.saveTask()

        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiTask>()).first)
        XCTAssertEqual(task.title, "Call Sam tomorrow at 3pm")
        XCTAssertEqual(task.quadrant, TodoSection.urgentImportant.quadrant)
        XCTAssertTrue(model.tasksMarkedUrgent.contains(task.id))

        model.undoAutoUrgent(task)
        XCTAssertFalse(model.isUrgent(task))
        XCTAssertEqual(task.urgentOverride, false)
        XCTAssertEqual(task.quadrant, TodoSection.notUrgentImportant.quadrant)
    }

    func testHabitScheduleMinimumAndCheckInPersist() throws {
        let context = try makeContext()
        let model = TodoViewModel()
        model.load(context)
        model.beginHabit()
        model.habitDraft.title = "Read"
        model.habitDraft.schedule = "someDays"
        XCTAssertFalse(model.canSaveHabit)
        model.habitDraft.weekdays = [2, 4, 6]
        XCTAssertTrue(model.canSaveHabit)
        model.habitDraft.reminderHour = 8
        model.habitDraft.minimumVersion = "one page"
        model.habitDraft.stackingCue = "make coffee"
        model.habitDraft.identity = "a reader"
        model.saveHabit()

        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<KoiHabit>()).first)
        XCTAssertEqual(habit.schedule, "someDays")
        XCTAssertEqual(habit.weekdays, [2, 4, 6])
        XCTAssertEqual(habit.minimumVersion, "one page")
        XCTAssertEqual(habit.stackingCue, "make coffee")
        XCTAssertEqual(habit.identity, "a reader")

        model.load(context)
        model.toggleHabit(habit, minimum: true)
        XCTAssertEqual(model.todayCompletion(for: habit), 1)
        model.toggleHabit(habit)
        XCTAssertEqual(model.todayCompletion(for: habit), 0)
    }

    func testTaskMovesAcrossMatrixAndCompletes() throws {
        let context = try makeContext()
        let task = KoiTask(title: "Draft plan", quadrant: TodoSection.someday.quadrant)
        context.insert(task)
        try context.save()
        let model = TodoViewModel()
        model.load(context)

        model.move(task, to: .urgentImportant)
        XCTAssertEqual(model.currentSection(for: task), .urgentImportant)
        XCTAssertTrue(task.important)
        model.toggleCompletion(task)
        XCTAssertTrue(task.isComplete)
        XCTAssertNotNil(task.completedAt)
    }

    func testCompletedTaskAppearsInArchiveAfterOneDayAndCanRestore() throws {
        let context = try makeContext()
        let task = KoiTask(title: "Sent note", isComplete: true)
        task.completedAt = Calendar.current.date(byAdding: .day, value: -2, to: .now)
        context.insert(task)
        try context.save()
        let model = TodoViewModel()
        model.load(context)

        XCTAssertEqual(model.archivedTasks.map(\.title), ["Sent note"])
        model.restoreTask(task)
        XCTAssertFalse(task.isComplete)
        XCTAssertNil(task.archivedAt)
    }

    func testDueInThreeDaysDoesNotChangeUrgency() throws {
        let context = try makeContext()
        let dueDate = Calendar.current.date(byAdding: .day, value: 3, to: .now)
        let task = KoiTask(title: "Plan outing", dueAt: dueDate, quadrant: TodoSection.notUrgentImportant.quadrant)
        context.insert(task)
        try context.save()
        let model = TodoViewModel()
        model.load(context)
        XCTAssertEqual(task.quadrant, TodoSection.notUrgentImportant.quadrant)
        XCTAssertFalse(model.tasksMarkedUrgent.contains(task.id))
    }

    func testStartupAutoUrgencyDoesNotShowUndoToast() throws {
        let context = try makeContext()
        let dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        let task = KoiTask(title: "Finish draft", dueAt: dueDate, quadrant: TodoSection.notUrgentImportant.quadrant)
        context.insert(task)
        try context.save()

        let model = TodoViewModel()
        model.load(context)

        XCTAssertEqual(task.quadrant, TodoSection.urgentImportant.quadrant)
        XCTAssertNil(model.toast)
    }

    private func makeContext() throws -> ModelContext {
        let container = try KoiSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }
}
