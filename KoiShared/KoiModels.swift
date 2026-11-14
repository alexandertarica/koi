import Foundation
import SwiftData

@Model
public final class KoiDay {
    @Attribute(.unique) public var dayID: String
    public var date: Date
    public var balance: Double
    public var habitsScore: Double
    public var nutritionScore: Double
    public var exerciseScore: Double

    public init(date: Date, balance: Double = 0, habitsScore: Double = 0, nutritionScore: Double = 0, exerciseScore: Double = 0) {
        self.dayID = Self.identifier(for: date)
        self.date = date
        self.balance = balance
        self.habitsScore = habitsScore
        self.nutritionScore = nutritionScore
        self.exerciseScore = exerciseScore
    }

    private static func identifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

@Model
public final class KoiHabit {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var note: String
    public var isActive: Bool
    public var createdAt: Date
    public var schedule: String = "daily"
    public var weekdays: [Int] = []
    public var reminderTime: Date? = nil
    public var minimumVersion: String = ""
    public var stackingCue: String = ""
    public var identity: String = ""
    public var pausedAt: Date? = nil

    public init(title: String, note: String = "", isActive: Bool = true, createdAt: Date = .now, schedule: String = "daily", weekdays: [Int] = [], reminderTime: Date? = nil, minimumVersion: String = "", stackingCue: String = "", identity: String = "") {
        self.id = UUID()
        self.title = title
        self.note = note
        self.isActive = isActive
        self.createdAt = createdAt
        self.schedule = schedule
        self.weekdays = weekdays
        self.reminderTime = reminderTime
        self.minimumVersion = minimumVersion
        self.stackingCue = stackingCue
        self.identity = identity
        self.pausedAt = nil
    }
}

@Model
public final class KoiHabitLog {
    @Attribute(.unique) public var id: UUID
    public var habitID: UUID
    public var date: Date
    /// 0 is not done, 1 is the two-minute minimum, and 2 is complete.
    public var completion: Int = 0

    public init(habitID: UUID, date: Date = .now, completion: Int = 0) {
        self.id = UUID()
        self.habitID = habitID
        self.date = date
        self.completion = min(max(completion, 0), 2)
    }
}

@Model
public final class KoiTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String
    public var dueAt: Date?
    public var quadrant: Int
    public var isComplete: Bool
    public var createdAt: Date
    public var important: Bool = true
    public var urgentOverride: Bool? = nil
    public var completedAt: Date? = nil
    public var archivedAt: Date? = nil
    public var lastTouchedAt: Date = Date.now
    public var timeMinutes: Int = 30

    public init(title: String, notes: String = "", dueAt: Date? = nil, quadrant: Int = 1, isComplete: Bool = false, createdAt: Date = .now, important: Bool? = nil, urgentOverride: Bool? = nil, timeMinutes: Int = 30) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.quadrant = min(max(quadrant, 0), 3)
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.important = important ?? (quadrant == 0 || quadrant == 1)
        self.urgentOverride = urgentOverride
        self.completedAt = nil
        self.archivedAt = nil
        self.lastTouchedAt = createdAt
        self.timeMinutes = max(timeMinutes, 0)
    }
}

@Model
public final class KoiFoodEntry {
    @Attribute(.unique) public var id: UUID
    public var loggedAt: Date
    public var name: String
    public var calories: Double
    public var proteinGrams: Double
    public var carbohydrateGrams: Double
    public var fatGrams: Double
    public var fiberGrams: Double
    public var addedSugarGrams: Double
    public var sodiumMilligrams: Double
    public var confidence: Double = 1
    public var imageJPEG: Data? = nil
    public var notes: String = ""

    public init(name: String, loggedAt: Date = .now, calories: Double = 0, proteinGrams: Double = 0, carbohydrateGrams: Double = 0, fatGrams: Double = 0, fiberGrams: Double = 0, addedSugarGrams: Double = 0, sodiumMilligrams: Double = 0, confidence: Double = 1, imageJPEG: Data? = nil, notes: String = "") {
        self.id = UUID()
        self.loggedAt = loggedAt
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.addedSugarGrams = addedSugarGrams
        self.sodiumMilligrams = sodiumMilligrams
        self.confidence = min(max(confidence, 0), 1)
        self.imageJPEG = imageJPEG
        self.notes = notes
    }
}

@Model
public final class KoiNutrientGoal {
    @Attribute(.unique) public var key: String
    public var name: String
    public var unit: String
    public var goal: Double
    public var step: Double
    public var goalType: String
    public var isActive: Bool

    public init(key: String, name: String, unit: String, goal: Double, step: Double, goalType: String = "reach", isActive: Bool = true) {
        self.key = key
        self.name = name
        self.unit = unit
        self.goal = max(goal.isFinite ? goal : 0, 0)
        self.step = max(step.isFinite ? step : 1, 1)
        self.goalType = goalType
        self.isActive = isActive
    }
}

@Model
public final class KoiNutrientEntry {
    @Attribute(.unique) public var id: String
    public var dayID: String
    public var nutrientKey: String
    /// Signed adjustment layered over meal totals. Negative values let the user
    /// set a daily counter below the nutrition already contained in meal logs.
    public var value: Double

    public init(date: Date, nutrientKey: String, value: Double = 0) {
        let dayID = Self.dayIdentifier(for: date)
        self.dayID = dayID
        self.nutrientKey = nutrientKey
        self.id = "\(dayID)|\(nutrientKey)"
        self.value = value.isFinite ? value : 0
    }

    private static func dayIdentifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

@Model
public final class KoiSupplement {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var isActive: Bool

    public init(name: String, isActive: Bool = true) {
        self.id = UUID()
        self.name = name
        self.isActive = isActive
    }
}

@Model
public final class KoiSupplementLog {
    @Attribute(.unique) public var id: String
    public var supplementID: UUID
    public var dayID: String
    public var isTaken: Bool

    public init(supplementID: UUID, date: Date, isTaken: Bool = false) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dayID = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        self.supplementID = supplementID
        self.dayID = dayID
        self.id = "\(dayID)|\(supplementID.uuidString)"
        self.isTaken = isTaken
    }
}

@Model
public final class KoiMovementGoal {
    @Attribute(.unique) public var id: String
    public var stepGoal: Int
    public var weeklyWorkoutGoal: Int
    public var healthEnabled: Bool

    public init(stepGoal: Int = 8_000, weeklyWorkoutGoal: Int = 4, healthEnabled: Bool = false) {
        self.id = "movement"
        self.stepGoal = max(stepGoal, 1)
        self.weeklyWorkoutGoal = max(weeklyWorkoutGoal, 1)
        self.healthEnabled = healthEnabled
    }
}

@Model
public final class KoiMovementDay {
    @Attribute(.unique) public var dayID: String
    public var date: Date
    public var healthSteps: Int?
    public var manualStepAdjustment: Int
    public var healthWorkoutCount: Int
    public var didManuallyTrain: Bool

    public init(date: Date, healthSteps: Int? = nil, manualStepAdjustment: Int = 0, healthWorkoutCount: Int = 0, didManuallyTrain: Bool = false) {
        self.dayID = Self.identifier(for: date)
        self.date = date
        self.healthSteps = healthSteps.map { max($0, 0) }
        self.manualStepAdjustment = manualStepAdjustment
        self.healthWorkoutCount = max(healthWorkoutCount, 0)
        self.didManuallyTrain = didManuallyTrain
    }

    public var steps: Int { max((healthSteps ?? 0) + manualStepAdjustment, 0) }
    public var workoutCount: Int { max(healthWorkoutCount, didManuallyTrain ? 1 : 0) }
    public var isTrainingDay: Bool { didManuallyTrain || healthWorkoutCount > 0 }

    private static func identifier(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

@Model
public final class KoiWorkoutRoutine {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var muscleGroup: String
    public var createdAt: Date
    public var plannedAt: Date? = nil

    public init(name: String, muscleGroup: String = "full body", createdAt: Date = .now, plannedAt: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.createdAt = createdAt
        self.plannedAt = plannedAt
    }
}

@Model
public final class KoiRoutineLift {
    @Attribute(.unique) public var id: UUID
    public var routineID: UUID
    public var name: String
    public var muscleGroup: String
    public var targetSets: Int
    public var targetReps: Int
    public var order: Int
    public var restSeconds: Int

    public init(routineID: UUID, name: String, muscleGroup: String? = nil, targetSets: Int = 3, targetReps: Int = 8, order: Int = 0, restSeconds: Int = 90) {
        self.id = UUID()
        self.routineID = routineID
        self.name = name
        self.muscleGroup = muscleGroup ?? "full body"
        self.targetSets = min(max(targetSets, 1), 12)
        self.targetReps = min(max(targetReps, 1), 100)
        self.order = max(order, 0)
        self.restSeconds = min(max(restSeconds, 15), 600)
    }
}

@Model
public final class KoiWorkoutSession {
    @Attribute(.unique) public var id: UUID
    public var routineID: UUID? = nil
    public var name: String
    public var muscleGroup: String
    public var startedAt: Date
    public var endedAt: Date? = nil
    public var restUntil: Date? = nil
    public var isComplete: Bool = false

    public init(name: String = "Workout", muscleGroup: String = "full body", routineID: UUID? = nil, startedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.routineID = routineID
        self.startedAt = startedAt
        self.endedAt = nil
        self.restUntil = nil
        self.isComplete = false
    }
}

@Model
public final class KoiWorkoutLift {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var name: String
    public var muscleGroup: String
    public var order: Int
    public var targetSets: Int
    public var targetReps: Int
    public var restSeconds: Int

    public init(sessionID: UUID, name: String, muscleGroup: String? = nil, order: Int = 0, targetSets: Int = 3, targetReps: Int = 8, restSeconds: Int = 90) {
        self.id = UUID()
        self.sessionID = sessionID
        self.name = name
        self.muscleGroup = muscleGroup ?? "full body"
        self.order = max(order, 0)
        self.targetSets = min(max(targetSets, 1), 12)
        self.targetReps = min(max(targetReps, 1), 100)
        self.restSeconds = min(max(restSeconds, 15), 600)
    }
}

@Model
public final class KoiWorkoutSet {
    @Attribute(.unique) public var id: UUID
    public var sessionID: UUID
    public var liftID: UUID
    public var loggedAt: Date
    public var weightLB: Double
    public var reps: Int
    public var isWarmUp: Bool
    public var isBodyweight: Bool

    public init(sessionID: UUID, liftID: UUID, loggedAt: Date = .now, weightLB: Double, reps: Int, isWarmUp: Bool = false, isBodyweight: Bool = false) {
        self.id = UUID()
        self.sessionID = sessionID
        self.liftID = liftID
        self.loggedAt = loggedAt
        self.weightLB = weightLB.isFinite ? max(weightLB, 0) : 0
        self.reps = min(max(reps, 0), 1_000)
        self.isWarmUp = isWarmUp
        self.isBodyweight = isBodyweight
    }
}

@Model
public final class KoiCardioSession {
    @Attribute(.unique) public var id: UUID
    public var activity: String
    public var detail: String
    public var startedAt: Date
    public var endedAt: Date? = nil
    public var durationSeconds: Int
    public var distanceMeters: Double
    public var routeData: Data? = nil
    public var mileSplitsData: Data? = nil
    public var isComplete: Bool = false

    public init(activity: String, detail: String = "", startedAt: Date = .now, durationSeconds: Int = 0, distanceMeters: Double = 0) {
        self.id = UUID()
        self.activity = activity
        self.detail = detail
        self.startedAt = startedAt
        self.durationSeconds = max(durationSeconds, 0)
        self.distanceMeters = distanceMeters.isFinite ? max(distanceMeters, 0) : 0
        self.endedAt = nil
        self.routeData = nil
        self.mileSplitsData = nil
        self.isComplete = false
    }

    public var paceSecondsPerMile: Double? {
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) / (distanceMeters / 1_609.344)
    }
}
