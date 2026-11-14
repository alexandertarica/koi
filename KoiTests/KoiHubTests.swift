import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
final class KoiHubTests: XCTestCase {
    func testHubLoadsAndCompletesHabitAndDueTask() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = KoiHabit(title: "Read")
        let task = KoiTask(title: "Send the note", dueAt: .now)
        context.insert(habit)
        context.insert(task)
        try context.save()

        let model = HubViewModel(calendar: .current)
        model.refresh(using: context)

        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.balance.habits, 0.5, accuracy: 0.000_001)
        guard let habitItem = model.items.first(where: { $0.kind == .habit }),
              let taskItem = model.items.first(where: { $0.kind == .task }) else {
            return XCTFail("The Hub should show the active habit and today's task.")
        }

        model.toggle(habitItem)
        model.toggle(taskItem)

        XCTAssertEqual(model.items.filter(\.isComplete).count, 2)
        XCTAssertEqual(model.balance.habits, 1)
        XCTAssertEqual(model.balance.score, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertTrue(task.isComplete)
    }

    func testScrubbingBackHidesItemsCreatedToday() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = KoiHabit(title: "Read")
        let task = KoiTask(title: "Send the note", dueAt: .now)
        context.insert(habit)
        context.insert(task)
        try context.save()

        let model = HubViewModel(calendar: .current)
        model.refresh(using: context)
        model.selectDay(daysAgo: 1)

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.selectedDayOffset, 1)
    }
}
