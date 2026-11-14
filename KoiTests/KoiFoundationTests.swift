import XCTest
import SwiftData
import KoiShared

final class KoiFoundationTests: XCTestCase {
    func testInMemoryContainerCanPersistCoreModels() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let day = KoiDay(date: .now, balance: 0.72)
        context.insert(day)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KoiDay>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.balance, 0.72)
    }

    func testInMemoryContainerCanPersistAHabitCheckIn() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = KoiHabit(title: "Read")
        let log = KoiHabitLog(habitID: habit.id, completion: 2)
        context.insert(habit)
        context.insert(log)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KoiHabitLog>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.habitID, habit.id)
        XCTAssertEqual(fetched.first?.completion, 2)
    }

    func testWidgetSnapshotRoundTripsAndClampsPillarValues() throws {
        let habit = KoiWidgetHabit(id: UUID(), title: "Walk outside", isComplete: true)
        let snapshot = KoiWidgetSnapshot(day: "2026-11-14", balance: 112, habits: -4, nutrition: 62, exercise: 75, habitItems: [habit])
        let decoded = try JSONDecoder().decode(KoiWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.balance, 100)
        XCTAssertEqual(decoded.habits, 0)
        XCTAssertEqual(decoded.nutrition, 62)
        XCTAssertEqual(decoded.habitItems, [habit])
        XCTAssertEqual(decoded.habitsCompleted, 1)
        XCTAssertEqual(decoded.habitsTotal, 1)
    }
}
