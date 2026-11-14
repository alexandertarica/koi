import Foundation

enum NutrientGoalType: String, Codable, CaseIterable, Sendable {
    case reach
    case limit
    case around
    case track
}

struct NutrientGoalInput: Equatable, Sendable {
    let key: String
    let goal: Double
    let type: NutrientGoalType
}

struct NutritionScore: Equatable, Sendable {
    let score: Double
    let contributions: [String: Double]
}

struct MealNutritionInput: Equatable, Sendable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let addedSugar: Double
    let sodium: Double
}

struct NutritionAdjustmentInput: Equatable, Sendable {
    let key: String
    let value: Double
}

enum NutritionEngine {
    static func totals(meals: [MealNutritionInput], adjustments: [NutritionAdjustmentInput]) -> [String: Double] {
        var values: [String: Double] = [:]
        for meal in meals {
            values["calories", default: 0] += meal.calories
            values["protein", default: 0] += meal.protein
            values["carbs", default: 0] += meal.carbs
            values["fat", default: 0] += meal.fat
            values["fiber", default: 0] += meal.fiber
            values["added_sugar", default: 0] += meal.addedSugar
            values["sodium", default: 0] += meal.sodium
        }
        for adjustment in adjustments where adjustment.value.isFinite {
            values[adjustment.key, default: 0] += adjustment.value
        }
        for key in values.keys { values[key] = finiteNonnegative(values[key] ?? 0) }
        return values
    }

    static func hasAnyIntake(meals: [MealNutritionInput], adjustments: [NutritionAdjustmentInput]) -> Bool {
        !meals.isEmpty || adjustments.contains { $0.value.isFinite && $0.value != 0 }
    }

    static func score(
        goals: [NutrientGoalInput],
        values: [String: Double],
        calories: Double,
        calorieGoal: Double,
        hasAnyIntake: Bool
    ) -> NutritionScore {
        guard hasAnyIntake else { return NutritionScore(score: 0, contributions: [:]) }
        let safeCalories = finiteNonnegative(calories)
        let calorieFactor = calorieGoal > 0 ? min(safeCalories / calorieGoal, 1) : 0
        var contributions: [String: Double] = [:]

        for item in goals where item.type != .track && item.goal.isFinite && item.goal > 0 {
            let value = finiteNonnegative(values[item.key] ?? 0)
            let contribution: Double
            switch item.type {
            case .reach:
                contribution = min(value / item.goal, 1)
            case .limit:
                let limitCredit = value <= item.goal ? 1 : item.goal / max(value, 1)
                contribution = limitCredit * calorieFactor
            case .around:
                contribution = 1 - min(abs(value - item.goal) / item.goal, 1)
            case .track:
                continue
            }
            contributions[item.key] = min(max(contribution.isFinite ? contribution : 0, 0), 1)
        }

        guard !contributions.isEmpty else { return NutritionScore(score: 0, contributions: [:]) }
        let average = contributions.values.reduce(0, +) / Double(contributions.count)
        return NutritionScore(score: min(max(average, 0), 1), contributions: contributions)
    }

    private static func finiteNonnegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }
}
