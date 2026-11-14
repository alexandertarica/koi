import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

enum ReadinessLevel: String, Equatable, Sendable {
    case ready = "Ready"
    case steady = "Steady"
    case takeItEasy = "Take it easy"
}

struct ReadinessReading: Equatable, Sendable {
    let level: ReadinessLevel
    let reasons: [String]
}

struct ReadinessInput: Equatable, Sendable {
    let sleepHours: Double?
    let sleepBaselineHours: Double?
    let hrv: Double?
    let hrvBaseline: Double?
    let restingHeartRate: Double?
    let restingHeartRateBaseline: Double?
}

enum ReadinessEngine {
    static func evaluate(_ input: ReadinessInput) -> ReadinessReading? {
        let comparisons: [(Double?, Double?, Bool, String)] = [
            (input.sleepHours, input.sleepBaselineHours, false, "Sleep was shorter than usual"),
            (input.hrv, input.hrvBaseline, false, "HRV was lower than usual"),
            (input.restingHeartRate, input.restingHeartRateBaseline, true, "Resting heart rate was higher than usual")
        ]
        let available = comparisons.compactMap { current, baseline, higherIsWorse, reason -> (Bool, String)? in
            guard let current, let baseline, current.isFinite, baseline.isFinite, baseline > 0 else { return nil }
            let delta = (current - baseline) / baseline
            return (higherIsWorse ? delta > 0.10 : delta < -0.10, reason)
        }
        guard !available.isEmpty else { return nil }
        let concerns = available.filter(\.0).map(\.1)
        let level: ReadinessLevel = concerns.count >= 2 ? .takeItEasy : (concerns.isEmpty ? .ready : .steady)
        return ReadinessReading(level: level, reasons: concerns.isEmpty ? ["Your recovery is close to your usual range"] : concerns)
    }
}

enum HabitCoachAction: Equatable, Sendable {
    case easeOff
    case stepUp(minimum: String)
    case graduate
    case stack(after: String)
}

struct HabitCoachInput: Equatable, Sendable {
    let scheduledDays: Int
    let completedDays: Int
    let minimumDays: Int
    let consecutiveStrongWeeks: Int
    let activeDays: Int
    let strongestHabitTitle: String?
}

enum HabitCoachEngine {
    static func suggestion(_ habits: [HabitCoachInput]) -> (index: Int, action: HabitCoachAction)? {
        for (index, habit) in habits.enumerated() where habit.scheduledDays > 0 {
            if habit.activeDays >= 66 && habit.completedDays * 10 >= habit.scheduledDays * 9 { return (index, .graduate) }
            if habit.consecutiveStrongWeeks >= 4 && habit.scheduledDays > 0 { return (index, .stepUp(minimum: "Keep the current amount as your minimum.")) }
            if habit.completedDays * 2 < habit.scheduledDays || habit.minimumDays * 2 >= habit.scheduledDays { return (index, .easeOff) }
        }
        guard let strongest = habits.first(where: { $0.completedDays > 0 })?.strongestHabitTitle else { return nil }
        return (habits.count, .stack(after: strongest))
    }
}

struct PlateLoad: Equatable, Sendable {
    let barWeight: Double
    let platesPerSide: [Double]
    let isExact: Bool
    let usableWeight: Double
}

enum PlateMath {
    static let standardPlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    static func load(weight: Double, bar: Double, plates: [Double] = standardPlates) -> PlateLoad {
        guard weight.isFinite, bar.isFinite, weight >= 0, bar >= 0 else {
            return PlateLoad(barWeight: max(bar.isFinite ? bar : 0, 0), platesPerSide: [], isExact: false, usableWeight: max(bar.isFinite ? bar : 0, 0))
        }
        let valid = plates.filter { $0.isFinite && $0 > 0 }.sorted(by: >)
        let target = max(weight - bar, 0) / 2
        var remaining = target
        var selected: [Double] = []
        for plate in valid {
            while remaining + 0.0001 >= plate { selected.append(plate); remaining -= plate }
        }
        let usable = bar + selected.reduce(0, +) * 2
        return PlateLoad(barWeight: bar, platesPerSide: selected, isExact: abs(usable - weight) < 0.001, usableWeight: usable)
    }
}

enum SmartNoteAction: Equatable, Sendable {
    case food(String)
    case water(Double)
    case habit(String)
    case task(String, Date?)
    case workout(name: String, weight: Double, reps: Int, sets: Int)
    case planLift(String)
}

enum SmartNoteParser {
    static func isActivityWithoutFood(_ rawText: String) -> Bool {
        let words = Set(rawText.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let activityWords: Set<String> = ["walk", "walked", "walking", "ran", "run", "running", "jog", "jogged", "cycled", "cycling", "hiked", "hiking", "trained", "training"]
        let foodActionWords: Set<String> = ["ate", "eat", "eating", "had", "having", "drank", "drink", "drinking", "meal", "snack"]
        return !words.isDisjoint(with: activityWords) && words.isDisjoint(with: foodActionWords)
    }

    static func parse(_ rawText: String, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> SmartNoteAction? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8000 else { return nil }
        guard !isActivityWithoutFood(text) else { return nil }
        let lower = text.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if lower.contains("water") || lower.contains("drank") {
            let number = firstNumber(in: lower) ?? 8
            return .water(number)
        }
        if !words.isDisjoint(with: ["bench", "squat", "deadlift", "press", "row", "curl"]) {
            let pattern = #"(\d+(?:\.\d+)?)\s*(?:lb|lbs)?\s*[x×]\s*(\d+)\s*(?:x|×)\s*(\d+)"#
            if let match = text.range(of: pattern, options: .regularExpression),
               let regex = try? NSRegularExpression(pattern: pattern),
               let result = regex.firstMatch(in: text, range: NSRange(match, in: text)),
               let weightRange = Range(result.range(at: 1), in: text),
               let repsRange = Range(result.range(at: 2), in: text),
               let setsRange = Range(result.range(at: 3), in: text),
               let weight = Double(text[weightRange]), let reps = Int(text[repsRange]), let sets = Int(text[setsRange]) {
                let name = String(text[..<weightRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return .workout(name: name.isEmpty ? "Workout" : name, weight: weight, reps: reps, sets: sets)
            }
            return .planLift(text)
        }
        if lower.contains("done") || lower.contains("did") || lower.contains("finished") { return .habit(text) }
        if lower.contains("today") || lower.contains("tomorrow") || lower.contains("task") || lower.contains("todo") {
            return .task(text, DateParsing.parse(text, relativeTo: now, calendar: calendar)?.date)
        }
        return .food(text)
    }

    private static func firstNumber(in text: String) -> Double? {
        guard let range = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[range])
    }
}

#if canImport(FoundationModels)
@Generable
struct GeneratedSmartNoteAction {
    @Guide(description: "One of food, water, habit, task, workout, or planLift") var category: String
    @Guide(description: "The concise food, habit, task, or exercise name") var subject: String
    @Guide(description: "A water amount in ounces, or the workout weight in pounds; empty if absent") var amount: String
    @Guide(description: "Workout repetitions, or empty if absent") var reps: String
    @Guide(description: "Workout set count, or empty if absent") var sets: String
    @Guide(description: "A date phrase from the note, or empty if none") var date: String
}

enum SmartNoteClassifier {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func classify(_ text: String, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async -> SmartNoteAction? {
        guard isAvailable, text.count <= 8_000 else { return nil }
        let session = LanguageModelSession(instructions: "Classify a note into one Koi action. Return only the requested fields. Never invent amounts, dates, or exercise details. A food description is food. Water mentions are water. A completed routine is habit only when it names a habit. A task with a due phrase is task. A named lift with weight, reps, and sets is workout; otherwise it is planLift.")
        do {
            let response = try await session.respond(to: "Classify this user note: \(text)", generating: GeneratedSmartNoteAction.self)
            let item = response.content
            let subject = item.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = Double(item.amount)
            switch item.category.lowercased() {
            case "food": return subject.isEmpty ? nil : .food(subject)
            case "water": return .water(amount ?? 8)
            case "habit": return subject.isEmpty ? nil : .habit(subject)
            case "task":
                let title = [subject, item.date].filter { !$0.isEmpty }.joined(separator: " ")
                return title.isEmpty ? nil : .task(title, DateParsing.parse(title, relativeTo: now, calendar: calendar)?.date)
            case "workout":
                guard let weight = amount, let reps = Int(item.reps), let sets = Int(item.sets), !subject.isEmpty else { return nil }
                return .workout(name: subject, weight: weight, reps: reps, sets: sets)
            case "planlift": return subject.isEmpty ? nil : .planLift(subject)
            default: return nil
            }
        } catch { return nil }
    }
}
#else
enum SmartNoteClassifier {
    static let isAvailable = false
    static func classify(_ text: String, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async -> SmartNoteAction? { nil }
}
#endif

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

    static func nextStep(lastSets: [WorkoutSetResult], targetReps: Int, targetSets: Int? = nil, isBodyweight: Bool, holdWeight: Bool = false) -> WorkoutProgression? {
        guard let lastSet = lastSets.last else { return nil }
        let target = max(targetReps, 1)
        if holdWeight {
            return WorkoutProgression(weightLB: lastSet.weightLB, reps: target, reason: "Recovery is low. Hold your usual weight.")
        }
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
