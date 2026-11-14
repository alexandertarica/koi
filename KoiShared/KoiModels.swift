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

    public init(title: String, note: String = "", isActive: Bool = true, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

@Model
public final class KoiHabitLog {
    @Attribute(.unique) public var id: UUID
    public var habitID: UUID
    public var date: Date
    /// 0 is not done, 1 is the two-minute minimum, and 2 is complete.
    public var completion: Int

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

    public init(title: String, notes: String = "", dueAt: Date? = nil, quadrant: Int = 1, isComplete: Bool = false, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.quadrant = quadrant
        self.isComplete = isComplete
        self.createdAt = createdAt
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

    public init(name: String, loggedAt: Date = .now, calories: Double = 0, proteinGrams: Double = 0, carbohydrateGrams: Double = 0, fatGrams: Double = 0, fiberGrams: Double = 0, addedSugarGrams: Double = 0, sodiumMilligrams: Double = 0) {
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
    }
}
