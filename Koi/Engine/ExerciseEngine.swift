import Foundation

struct ExerciseDayInput: Equatable, Sendable {
    let steps: Int
    let stepGoal: Int
    let isTrainingDay: Bool
    let workoutsInLastSevenDays: Int
    let weeklyWorkoutGoal: Int
}

struct ExerciseScore: Equatable, Sendable {
    let score: Double
    let stepScore: Double
    let trainingScore: Double
}

enum ExerciseEngine {
    static func score(_ input: ExerciseDayInput) -> ExerciseScore {
        let goal = max(input.stepGoal, 1)
        let stepScore = min(Double(max(input.steps, 0)) / Double(goal), 1)
        let weeklyGoal = max(input.weeklyWorkoutGoal, 1)
        let trainingScore = input.isTrainingDay
            ? 1
            : min(Double(max(input.workoutsInLastSevenDays, 0)) / Double(weeklyGoal), 1)
        return ExerciseScore(score: (stepScore + trainingScore) / 2, stepScore: stepScore, trainingScore: trainingScore)
    }
}
