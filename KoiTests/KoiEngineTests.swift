import XCTest
@testable import Koi

final class KoiEngineTests: XCTestCase {
    func testBalanceUsesEachFocusWeightAndCapsPillars() {
        let ritual = BalanceEngine.score(
            pillars: BalancePillars(habits: 1.2, nutrition: 0.4, exercise: -1),
            focus: .ritualist
        )

        XCTAssertEqual(ritual.habits, 1)
        XCTAssertEqual(ritual.nutrition, 0.4)
        XCTAssertEqual(ritual.exercise, 0)
        XCTAssertEqual(ritual.score, 0.6, accuracy: 0.000_001)
    }

    func testBalanceReturnsZeroForNonFinitePillar() {
        let result = BalanceEngine.score(pillars: BalancePillars(habits: .nan, nutrition: .infinity, exercise: 1))
        XCTAssertEqual(result.score, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(result.habits, 0)
        XCTAssertEqual(result.nutrition, 0)
    }

    func testOverflowingFiniteWeightsFallBackToEqualFocus() {
        let weights = BalanceWeights(
            habits: .greatestFiniteMagnitude,
            nutrition: .greatestFiniteMagnitude,
            exercise: .greatestFiniteMagnitude
        )
        XCTAssertEqual(weights, BalanceWeights(habits: 1, nutrition: 1, exercise: 1))
    }

    func testHabitMinimumAndFirstMissEarnHalfCredit() {
        let minimum = HabitRules.credit(for: HabitDayInput(isScheduled: true, completion: .minimum), previousScheduledMisses: 0)
        let firstMiss = HabitRules.credit(for: HabitDayInput(isScheduled: true), previousScheduledMisses: 0)
        let secondMiss = HabitRules.credit(for: HabitDayInput(isScheduled: true), previousScheduledMisses: 1)

        XCTAssertEqual(minimum.earned, 0.5)
        XCTAssertEqual(firstMiss.earned, 0.5)
        XCTAssertEqual(secondMiss.earned, 0)
    }

    func testHabitScoreIgnoresUnscheduledAndGraduatedHabits() {
        let inputs = [
            HabitDayInput(isScheduled: false, completion: .complete),
            HabitDayInput(isScheduled: true, completion: .complete, graduated: true),
            HabitDayInput(isScheduled: true, completion: .minimum)
        ]

        XCTAssertEqual(HabitRules.dayScore(inputs), 0.5)
        XCTAssertEqual(HabitRules.dayScore([HabitDayInput(isScheduled: false)]), 0)
    }

    func testHabitMissCounterOnlyAdvancesOnScheduledMisses() {
        let missed = HabitDayInput(isScheduled: true)
        let restDay = HabitDayInput(isScheduled: false)
        let done = HabitDayInput(isScheduled: true, completion: .complete)

        XCTAssertEqual(HabitRules.scheduledMisses(after: missed, previousScheduledMisses: 0), 1)
        XCTAssertEqual(HabitRules.scheduledMisses(after: restDay, previousScheduledMisses: 1), 1)
        XCTAssertEqual(HabitRules.scheduledMisses(after: done, previousScheduledMisses: 1), 0)
    }

    func testStreakAwardsAtSevenCountingDaysAndCapsFreezesAtTwo() {
        let start = date(2026, 1, 1)
        let days = (0..<16).compactMap { offset -> BalanceDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return BalanceDay(date: day, score: 0.7)
        }
        let today = date(2026, 1, 16)
        let result = StreakEngine.calculate(days: days, today: today, calendar: calendar)

        XCTAssertEqual(result.current, 16)
        XCTAssertEqual(result.best, 16)
        XCTAssertEqual(result.freezes, 2)
    }

    func testMissSpendsAFrozenDayWithoutEndingStreak() {
        let days = [
            BalanceDay(date: date(2026, 1, 1), score: 0.9),
            BalanceDay(date: date(2026, 1, 2), score: 0.9),
            BalanceDay(date: date(2026, 1, 3), score: 0.9),
            BalanceDay(date: date(2026, 1, 4), score: 0.9),
            BalanceDay(date: date(2026, 1, 5), score: 0.9),
            BalanceDay(date: date(2026, 1, 6), score: 0.2),
            BalanceDay(date: date(2026, 1, 7), score: 0.9)
        ]
        let result = StreakEngine.calculate(days: days, today: date(2026, 1, 7), calendar: calendar, initialFreezes: 1)

        XCTAssertEqual(result.current, 6)
        XCTAssertEqual(result.best, 6)
        XCTAssertEqual(result.freezes, 0)
    }

    func testTodayNeverBreaksAStreakBeforeTheDayEnds() {
        let days = [
            BalanceDay(date: date(2026, 1, 6), score: 0.8),
            BalanceDay(date: date(2026, 1, 7), score: 0.1)
        ]
        let result = StreakEngine.calculate(days: days, today: date(2026, 1, 7), calendar: calendar)
        XCTAssertEqual(result.current, 1)
        XCTAssertEqual(result.best, 1)
    }

    func testMissingHistoryDayConsumesFreezeOrBreaksStreak() {
        let days = [
            BalanceDay(date: date(2026, 1, 1), score: 0.9),
            BalanceDay(date: date(2026, 1, 3), score: 0.9)
        ]
        let protected = StreakEngine.calculate(days: days, today: date(2026, 1, 3), calendar: calendar, initialFreezes: 1)
        let broken = StreakEngine.calculate(days: days, today: date(2026, 1, 3), calendar: calendar)

        XCTAssertEqual(protected.current, 2)
        XCTAssertEqual(protected.freezes, 0)
        XCTAssertEqual(broken.current, 1)
    }

    func testBalanceExactlyAtThresholdCounts() {
        let result = StreakEngine.calculate(
            days: [BalanceDay(date: date(2026, 1, 1), score: 0.7)],
            today: date(2026, 1, 1),
            calendar: calendar
        )
        XCTAssertEqual(result.current, 1)
    }

    func testParsesTomorrowWeekdayAndClockTimeInInjectedCalendar() throws {
        let reference = date(2026, 11, 13, hour: 14)

        let tomorrow = try XCTUnwrap(DateParsing.parse("Call tomorrow at 3pm", relativeTo: reference, calendar: calendar))
        XCTAssertEqual(tomorrow.matchedText, "tomorrow at 3pm")
        XCTAssertEqual(tomorrow.date, date(2026, 11, 14, hour: 15))

        let friday = try XCTUnwrap(DateParsing.parse("Send it Friday", relativeTo: reference, calendar: calendar))
        XCTAssertEqual(friday.date, date(2026, 11, 20))
    }

    func testTimeAloneUsesNextOccurrence() throws {
        let afternoon = try XCTUnwrap(DateParsing.parse("at 3pm", relativeTo: date(2026, 11, 13, hour: 14), calendar: calendar))
        let tomorrow = try XCTUnwrap(DateParsing.parse("at 3pm", relativeTo: date(2026, 11, 13, hour: 16), calendar: calendar))

        XCTAssertEqual(afternoon.date, date(2026, 11, 13, hour: 15))
        XCTAssertEqual(tomorrow.date, date(2026, 11, 14, hour: 15))
    }

    func testInvalidTimeAndUnrecognizedTextReturnNoDate() {
        XCTAssertNil(DateParsing.parse("tomorrow at 13pm", relativeTo: date(2026, 11, 13), calendar: calendar))
        XCTAssertNil(DateParsing.parse("write a note", relativeTo: date(2026, 11, 13), calendar: calendar))
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components) ?? .distantPast
    }
}
