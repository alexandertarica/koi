import Foundation

struct BalanceDay: Sendable {
    let date: Date
    let score: Double
}

struct StreakResult: Equatable, Sendable {
    let current: Int
    let best: Int
    let freezes: Int
}

enum StreakEngine {
    static let countingThreshold = 0.70
    static let freezeInterval = 7
    static let maximumFreezes = 2

    static func calculate(
        days: [BalanceDay],
        today: Date,
        calendar inputCalendar: Calendar = .autoupdatingCurrent,
        initialFreezes: Int = 0
    ) -> StreakResult {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let todayStart = calendar.startOfDay(for: today)
        let grouped = Dictionary(grouping: days) { calendar.startOfDay(for: $0.date) }
        let orderedDates = grouped.keys.filter { $0 <= todayStart }.sorted()

        var current = 0
        var best = 0
        var freezes = min(max(initialFreezes, 0), maximumFreezes)
        var previousDate: Date?

        for date in orderedDates {
            guard let dayEntries = grouped[date] else { continue }
            if let previousDate,
               let expected = calendar.date(byAdding: .day, value: 1, to: previousDate),
               calendar.startOfDay(for: expected) != date {
                let gapDays = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 0
                if gapDays > 1 {
                    let bridgeCount = gapDays - 1
                    if date == todayStart {
                        current = max(0, current - max(0, bridgeCount - freezes))
                        freezes = max(0, freezes - min(bridgeCount, freezes))
                    } else if bridgeCount <= freezes {
                        freezes -= bridgeCount
                    } else {
                        current = 0
                        freezes = 0
                    }
                }
            }

            let score = dayEntries.map(\.score).max() ?? 0
            let qualifies = score.isFinite && score >= countingThreshold
            let isToday = date == todayStart

            if qualifies {
                current += 1
                best = max(best, current)
                if current > 0 && current.isMultiple(of: freezeInterval) {
                    freezes = min(maximumFreezes, freezes + 1)
                }
            } else if !isToday {
                if freezes > 0 {
                    freezes -= 1
                } else {
                    current = 0
                }
            }
            previousDate = date
        }

        return StreakResult(current: current, best: max(best, current), freezes: freezes)
    }
}
