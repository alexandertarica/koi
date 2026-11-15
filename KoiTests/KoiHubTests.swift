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

        let model = HubViewModel(calendar: .current, publishesWidgetSnapshot: false)
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

        let model = HubViewModel(calendar: .current, publishesWidgetSnapshot: false)
        model.refresh(using: context)
        model.selectDay(daysAgo: 1)

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.selectedDayOffset, 1)
    }

    func testPondSprintAveragesSelectedPillarsAndFindsWinner() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let middle = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        let sprint = PondSprint(recordName: "sprint-test", pillars: [.nutrition, .exercise], startDate: start, endDate: end, rule: "Coffee", createdBy: "alex")
        let scores = [
            PondDailyScore(username: "alex", date: start, habits: 0, nutrition: 0.6, exercise: 0.8, calendar: calendar),
            PondDailyScore(username: "alex", date: middle, habits: 0, nutrition: 0.6, exercise: 0.8, calendar: calendar),
            PondDailyScore(username: "alex", date: end, habits: 0, nutrition: 0.6, exercise: 0.8, calendar: calendar),
            PondDailyScore(username: "maya", date: start, habits: 0, nutrition: 0.9, exercise: 1, calendar: calendar),
            PondDailyScore(username: "maya", date: middle, habits: 0, nutrition: 0.9, exercise: 1, calendar: calendar),
            PondDailyScore(username: "maya", date: end, habits: 0, nutrition: 0.9, exercise: 1, calendar: calendar),
        ]
        let members = [PondMember(username: "alex", displayName: "Alex"), PondMember(username: "maya", displayName: "Maya")]
        let snapshot = PondSnapshot(currentUsername: "alex", name: "Pond", members: members, sprint: sprint, dailyScores: scores)

        XCTAssertEqual(PondEngine.score(for: "alex", sprint: sprint, scores: scores, through: end, calendar: calendar), 0.7, accuracy: 0.0001)
        XCTAssertEqual(PondEngine.winner(for: snapshot, through: end, calendar: calendar)?.member.username, "maya")
    }

    func testDemoPondSeedsFiveMembersAndRanksCurrentUserThird() {
        let service = InMemoryPondService.demo()
        let snapshot = service.cachedSnapshot!
        let model = PondViewModel(service: service)

        XCTAssertEqual(snapshot.members.count, 5)
        XCTAssertNotNil(snapshot.sprint)
        XCTAssertEqual(PondEngine.leaderboard(for: snapshot).first?.member.username, "alex")
        XCTAssertEqual(PondEngine.leaderboard(for: snapshot).first(where: { $0.member.username == "maya" })?.rank, 3)
        XCTAssertEqual(model.rankSummary, "3rd of 5 in your pond")
    }

    func testPondProfileFriendAndSprintFlowUsesInMemoryService() async {
        let friend = PondMember(username: "maya_7", displayName: "Maya")
        let service = InMemoryPondService(knownProfiles: [friend])
        let model = PondViewModel(service: service)
        model.username = "alex_7"
        await model.checkUsername(model.username)
        XCTAssertEqual(model.usernameStatus, .available)
        await model.createProfile(displayName: "Alex")
        model.friendUsername = "maya_7"
        await model.addFriend()
        model.pillars = [.nutrition, .exercise]
        model.rule = "Losers buy the winner a coffee"
        await model.startSprint()

        XCTAssertEqual(model.snapshot?.members.count, 2)
        XCTAssertEqual(model.snapshot?.sprint?.pillars, [.nutrition, .exercise])
        XCTAssertEqual(model.snapshot?.sprint?.rule, "Losers buy the winner a coffee")
    }
}
