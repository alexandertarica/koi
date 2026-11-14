import Foundation

enum BalanceFocus: String, CaseIterable, Sendable {
    case allRounder
    case ritualist
    case nourisher
    case mover

    var weights: BalanceWeights {
        switch self {
        case .allRounder: BalanceWeights(habits: 1 / 3, nutrition: 1 / 3, exercise: 1 / 3)
        case .ritualist: BalanceWeights(habits: 1 / 2, nutrition: 1 / 4, exercise: 1 / 4)
        case .nourisher: BalanceWeights(habits: 1 / 4, nutrition: 1 / 2, exercise: 1 / 4)
        case .mover: BalanceWeights(habits: 1 / 4, nutrition: 1 / 4, exercise: 1 / 2)
        }
    }
}

struct BalanceWeights: Equatable, Sendable {
    let habits: Double
    let nutrition: Double
    let exercise: Double

    init(habits: Double, nutrition: Double, exercise: Double) {
        guard habits.isFinite, nutrition.isFinite, exercise.isFinite else {
            self.habits = 1 / 3
            self.nutrition = 1 / 3
            self.exercise = 1 / 3
            return
        }
        let values = (max(0, habits), max(0, nutrition), max(0, exercise))
        let total = values.0 + values.1 + values.2
        guard total.isFinite, total > 0 else {
            self.habits = 1 / 3
            self.nutrition = 1 / 3
            self.exercise = 1 / 3
            return
        }
        self.habits = values.0 / total
        self.nutrition = values.1 / total
        self.exercise = values.2 / total
    }
}

struct BalancePillars: Equatable, Sendable {
    let habits: Double
    let nutrition: Double
    let exercise: Double
}

struct BalanceResult: Equatable, Sendable {
    let score: Double
    let habits: Double
    let nutrition: Double
    let exercise: Double
}

enum BalanceEngine {
    static func score(pillars: BalancePillars, focus: BalanceFocus = .allRounder) -> BalanceResult {
        score(pillars: pillars, weights: focus.weights)
    }

    static func score(pillars: BalancePillars, weights: BalanceWeights) -> BalanceResult {
        let habits = capped(pillars.habits)
        let nutrition = capped(pillars.nutrition)
        let exercise = capped(pillars.exercise)
        let score = capped(habits * weights.habits + nutrition * weights.nutrition + exercise * weights.exercise)
        return BalanceResult(score: score, habits: habits, nutrition: nutrition, exercise: exercise)
    }

    private static func capped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
