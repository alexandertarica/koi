import Foundation

enum WorkoutMuscleGroup: String, CaseIterable, Sendable {
    case push
    case pull
    case legs
    case core
    case upper
    case lower
    case fullBody = "full body"

    var label: String { rawValue.capitalized }
}

enum WorkoutNameRules {
    static func guessGroup(_ name: String) -> String {
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = normalized.split(whereSeparator: { !$0.isLetter })
        let names = Set(parts)
        if names.contains(where: { ["plank", "crunch", "situp", "ab", "core", "hollow"].contains(String($0)) }) { return WorkoutMuscleGroup.core.rawValue }
        if names.contains(where: { ["squat", "lunge", "leg", "hamstring", "quad", "calf", "deadlift", "hinge"].contains(String($0)) }) { return WorkoutMuscleGroup.legs.rawValue }
        if names.contains(where: { ["row", "pull", "lat", "bicep", "curl", "chinup", "facepull"].contains(String($0)) }) { return WorkoutMuscleGroup.pull.rawValue }
        if names.contains(where: { ["bench", "press", "chest", "push", "tricep", "dip", "fly", "shoulder"].contains(String($0)) }) { return WorkoutMuscleGroup.push.rawValue }
        return WorkoutMuscleGroup.fullBody.rawValue
    }

    static func guessRoutineGroup(_ name: String) -> String {
        let normalized = name.lowercased()
        if normalized.contains("upper") { return WorkoutMuscleGroup.upper.rawValue }
        if normalized.contains("lower") { return WorkoutMuscleGroup.lower.rawValue }
        if normalized.contains("full") || normalized.contains("total") { return WorkoutMuscleGroup.fullBody.rawValue }
        return guessGroup(name)
    }

    static func isBodyweight(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return ["push up", "push-up", "pull up", "pull-up", "chin up", "chin-up", "dip", "plank", "crunch", "sit up", "sit-up"].contains(where: normalized.contains)
    }
}

struct WorkoutRecommendationInput: Equatable, Sendable {
    let groupLastTrained: [String: Date]
    let lastRoutineNameByGroup: [String: String]
    let consecutiveTrainingDays: Int
    let plannedRoutine: WorkoutRoutineSummary?
    let routines: [WorkoutRoutineSummary]
}

struct WorkoutRoutineSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let plannedAt: Date?
}

struct WorkoutRecommendation: Equatable, Sendable {
    let group: String
    let routine: WorkoutRoutineSummary?
    let suggestsRest: Bool
    let reason: String
}

struct WorkoutSetResult: Equatable, Sendable {
    let weightLB: Double
    let reps: Int
    let estimatedOneRepMax: Double?
}

struct WorkoutProgression: Equatable, Sendable {
    let weightLB: Double
    let reps: Int
    let reason: String
}

enum WorkoutEngine {
    private static let preferredGroups = ["push", "pull", "legs", "core"]

    static func recommend(_ input: WorkoutRecommendationInput) -> WorkoutRecommendation {
        if let planned = input.plannedRoutine {
            return WorkoutRecommendation(group: planned.muscleGroup, routine: planned, suggestsRest: false, reason: "Planned for today")
        }
        if input.consecutiveTrainingDays >= 3 {
            return WorkoutRecommendation(group: "rest", routine: nil, suggestsRest: true, reason: "Three training days in a row")
        }
        if input.groupLastTrained.max(by: { $0.value < $1.value })?.key == WorkoutMuscleGroup.fullBody.rawValue {
            return WorkoutRecommendation(group: "rest", routine: nil, suggestsRest: true, reason: "A full-body day deserves a day off")
        }
        var groups = preferredGroups
        for routine in input.routines where ["upper", "lower", "full body"].contains(routine.muscleGroup) && !groups.contains(routine.muscleGroup) {
            groups.append(routine.muscleGroup)
        }
        let group = groups.min { lhs, rhs in
            let left = input.groupLastTrained[lhs] ?? .distantPast
            let right = input.groupLastTrained[rhs] ?? .distantPast
            if left == right { return (groups.firstIndex(of: lhs) ?? 0) < (groups.firstIndex(of: rhs) ?? 0) }
            return left < right
        } ?? "push"
        let routines = input.routines.filter { $0.muscleGroup == group }
        let lastRoutine = input.lastRoutineNameByGroup[group]
        let routine = group == "upper" && routines.count > 1
            ? (routines.first { $0.name.caseInsensitiveCompare(lastRoutine ?? "") != .orderedSame } ?? routines.first)
            : routines.first
        return WorkoutRecommendation(group: group, routine: routine, suggestsRest: false, reason: "Your \(group) group has had the longest rest")
    }

    static func nextStep(lastSets: [WorkoutSetResult], targetReps: Int, targetSets: Int? = nil, isBodyweight: Bool) -> WorkoutProgression? {
        guard let lastSet = lastSets.last else { return nil }
        let target = max(targetReps, 1)
        let reachedTop = lastSets.count >= max(targetSets ?? lastSets.count, 1) && lastSets.allSatisfy { $0.reps >= target }
        if isBodyweight {
            let reps = reachedTop ? max(lastSet.reps, target) + 1 : target
            return WorkoutProgression(weightLB: 0, reps: reps, reason: "Add a rep when every set reaches the top.")
        }
        guard lastSet.weightLB.isFinite, lastSet.weightLB >= 0 else { return nil }
        let increment = lastSet.weightLB < 50 ? 2.5 : 5
        if reachedTop {
            return WorkoutProgression(weightLB: lastSet.weightLB + increment, reps: target, reason: "Every set reached the top of the range.")
        }
        return WorkoutProgression(weightLB: lastSet.weightLB, reps: target, reason: "Hold the weight and build the reps.")
    }

    static func estimatedOneRepMax(weightLB: Double, reps: Int, isBodyweight: Bool = false) -> Double? {
        guard !isBodyweight, weightLB.isFinite, weightLB > 0, reps > 0 else { return nil }
        return weightLB * (1 + Double(reps) / 30)
    }
}
