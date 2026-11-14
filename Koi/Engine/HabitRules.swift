import Foundation

enum HabitCompletion: Sendable {
    case complete
    case minimum
    case missed
}

struct HabitDayInput: Sendable {
    let isScheduled: Bool
    let completion: HabitCompletion
    let graduated: Bool

    init(isScheduled: Bool, completion: HabitCompletion = .missed, graduated: Bool = false) {
        self.isScheduled = isScheduled
        self.completion = completion
        self.graduated = graduated
    }
}

struct HabitCredit: Equatable, Sendable {
    let earned: Double
    let possible: Double
    let score: Double
}

enum HabitRules {
    static func credit(for day: HabitDayInput, previousScheduledMisses: Int) -> HabitCredit {
        guard day.isScheduled, !day.graduated else {
            return HabitCredit(earned: 0, possible: 0, score: 0)
        }

        let earned: Double
        switch day.completion {
        case .complete:
            earned = 1
        case .minimum:
            earned = 0.5
        case .missed:
            earned = previousScheduledMisses == 0 ? 0.5 : 0
        }
        return HabitCredit(earned: earned, possible: 1, score: earned)
    }

    static func scheduledMisses(after day: HabitDayInput, previousScheduledMisses: Int) -> Int {
        guard day.isScheduled, !day.graduated else { return max(0, previousScheduledMisses) }
        return day.completion == .missed ? max(0, previousScheduledMisses) + 1 : 0
    }

    static func dayScore(_ days: [HabitDayInput], previousMisses: [Int] = []) -> Double {
        let scheduled = days.enumerated().compactMap { index, day -> HabitCredit? in
            guard day.isScheduled, !day.graduated else { return nil }
            let missed = index < previousMisses.count ? previousMisses[index] : 0
            return credit(for: day, previousScheduledMisses: missed)
        }
        guard !scheduled.isEmpty else { return 0 }
        return scheduled.reduce(0) { $0 + $1.earned } / Double(scheduled.count)
    }
}

extension HabitCompletion: Equatable {}
