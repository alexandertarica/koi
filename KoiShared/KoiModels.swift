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
