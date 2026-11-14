import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

struct IntakeNutrient: Identifiable {
    let key: String
    let name: String
    let unit: String
    let goal: Double
    let step: Double
    let goalType: NutrientGoalType
    let value: Double
    let contribution: Double?
    var id: String { key }
}

@MainActor
@Observable
final class IntakeViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Intake")
    private let calendar: Calendar
    private var context: ModelContext?
    private var manualEntries: [KoiNutrientEntry] = []
    private var supplementLogs: [KoiSupplementLog] = []

    private(set) var selectedDate: Date
    private(set) var goals: [KoiNutrientGoal] = []
    private(set) var meals: [KoiFoodEntry] = []
    private(set) var supplements: [KoiSupplement] = []
    private(set) var estimate: FoodEstimateValue?
    private(set) var estimatePhotoJPEG: Data?
    private(set) var isEstimating = false
    private(set) var errorMessage: String?
    private(set) var toast: String?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: .now)
    }

    var activeGoals: [KoiNutrientGoal] { goals.filter(\.isActive).sorted(by: Self.sortGoals) }
    var activeSupplements: [KoiSupplement] { supplements.filter(\.isActive).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var calories: Double { totals["calories"] ?? 0 }
    var calorieGoal: Double { activeGoals.first(where: { $0.key == "calories" })?.goal ?? 2_200 }
    var mealCount: Int { meals.count }
    var hasAnyIntake: Bool { NutritionEngine.hasAnyIntake(meals: mealInputs, adjustments: adjustmentInputs) }
    var score: NutritionScore {
        NutritionEngine.score(
            goals: activeGoals.map { NutrientGoalInput(key: $0.key, goal: $0.goal, type: NutrientGoalType(rawValue: $0.goalType) ?? .track) },
            values: totals,
            calories: calories,
            calorieGoal: calorieGoal,
            hasAnyIntake: hasAnyIntake
        )
    }
    var nutrientRows: [IntakeNutrient] {
        activeGoals.map { goal in
            IntakeNutrient(
                key: goal.key,
                name: goal.name,
                unit: goal.unit,
                goal: goal.goal,
                step: goal.step,
                goalType: NutrientGoalType(rawValue: goal.goalType) ?? .track,
                value: totals[goal.key] ?? 0,
                contribution: score.contributions[goal.key]
            )
        }
    }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            let storedGoals = try context.fetch(FetchDescriptor<KoiNutrientGoal>())
            let byKey = Set(storedGoals.map(\.key))
            var insertedDefault = false
            for preset in Self.defaultGoals where !byKey.contains(preset.key) {
                context.insert(KoiNutrientGoal(key: preset.key, name: preset.name, unit: preset.unit, goal: preset.goal, step: preset.step, goalType: preset.type.rawValue))
                insertedDefault = true
            }
            if insertedDefault { try context.save() }
            goals = try context.fetch(FetchDescriptor<KoiNutrientGoal>(sortBy: [SortDescriptor(\.key)]))
            let allMeals = try context.fetch(FetchDescriptor<KoiFoodEntry>(sortBy: [SortDescriptor(\.loggedAt)]))
            meals = allMeals.filter { calendar.isDate($0.loggedAt, inSameDayAs: selectedDate) }
            let dayID = Self.dayIdentifier(for: selectedDate, calendar: calendar)
            manualEntries = try context.fetch(FetchDescriptor<KoiNutrientEntry>()).filter { $0.dayID == dayID }
            supplements = try context.fetch(FetchDescriptor<KoiSupplement>(sortBy: [SortDescriptor(\.name)]))
            supplementLogs = try context.fetch(FetchDescriptor<KoiSupplementLog>()).filter { $0.dayID == dayID }
        } catch {
            logger.error("Unable to load Intake data.")
            errorMessage = "Couldn't load today's nutrition. Try again."
        }
    }

    func changeNutrient(_ key: String, by delta: Double) {
        setValue(key, to: max(0, (totals[key] ?? 0) + delta))
    }

    func setValue(_ key: String, to total: Double) {
        guard let context, let entry = manualEntries.first(where: { $0.nutrientKey == key }) ?? createManualEntry(key, in: context) else { return }
        entry.value = finite(total) - mealTotal(for: key)
        saveAndReload(context)
    }

    func setGoal(_ key: String, value: Double) {
        guard let context, let goal = goals.first(where: { $0.key == key }), value.isFinite, value > 0 else { return }
        goal.goal = value
        saveAndReload(context)
    }

    func setGoalType(_ key: String, type: NutrientGoalType) {
        guard let context, let goal = goals.first(where: { $0.key == key }) else { return }
        goal.goalType = type.rawValue
        saveAndReload(context)
    }

    func renameNutrient(_ key: String, name: String, unit: String) {
        guard let context, let goal = goals.first(where: { $0.key == key }) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanUnit.isEmpty else { return }
        goal.name = cleanName
        goal.unit = cleanUnit
        saveAndReload(context)
    }

    func removeNutrient(_ key: String) {
        guard let context, let goal = goals.first(where: { $0.key == key }) else { return }
        goal.isActive = false
        saveAndReload(context)
    }

    func addPreset(_ key: String) {
        guard let context, let preset = Self.availablePresets.first(where: { $0.key == key }) else { return }
        if let existing = goals.first(where: { $0.key == preset.key }) { existing.isActive = true }
        else { context.insert(KoiNutrientGoal(key: preset.key, name: preset.name, unit: preset.unit, goal: preset.goal, step: preset.step, goalType: preset.type.rawValue)) }
        saveAndReload(context)
    }

    func addCustomNutrient(name: String, unit: String, goal: Double, step: Double) {
        guard let context else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanUnit.isEmpty, goal.isFinite, goal > 0 else { return }
        let stem = Self.slug(cleanName)
        var key = "custom_\(stem)"
        var index = 2
        while goals.contains(where: { $0.key == key }) {
            key = "custom_\(stem)_\(index)"
            index += 1
        }
        context.insert(KoiNutrientGoal(key: key, name: cleanName, unit: cleanUnit, goal: goal, step: max(step, 1), goalType: NutrientGoalType.track.rawValue))
        saveAndReload(context)
    }

    func isSupplementTaken(_ supplement: KoiSupplement) -> Bool {
        supplementLogs.first(where: { $0.supplementID == supplement.id })?.isTaken ?? false
    }

    func toggleSupplement(_ supplement: KoiSupplement) {
        guard let context else { return }
        if let log = supplementLogs.first(where: { $0.supplementID == supplement.id }) { log.isTaken.toggle() }
        else {
            let log = KoiSupplementLog(supplementID: supplement.id, date: selectedDate, isTaken: true)
            context.insert(log)
            supplementLogs.append(log)
        }
        saveAndReload(context)
    }

    func addSupplement(name: String) {
        guard let context else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !supplements.contains(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame && $0.isActive }) else {
            toast = "That supplement is already here."
            return
        }
        context.insert(KoiSupplement(name: clean))
        saveAndReload(context)
    }

    func removeSupplement(_ supplement: KoiSupplement) {
        guard let context else { return }
        supplement.isActive = false
        saveAndReload(context)
    }

    func estimateMeal(text: String?, jpegData: Data?, using estimator: any FoodEstimating) async {
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }
        do {
            estimate = try await estimator.estimate(text: text, jpegData: jpegData)
            estimatePhotoJPEG = jpegData
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't estimate this meal. Enter the numbers yourself."
        } catch {
            errorMessage = "Couldn't estimate this meal. Enter the numbers yourself."
            logger.error("Food estimate failed.")
        }
    }

    func clearEstimate() { estimate = nil; estimatePhotoJPEG = nil; errorMessage = nil }

    func addMeal(_ value: FoodEstimateValue, note: String, jpegData: Data?) {
        guard let context else { return }
        context.insert(makeFoodEntry(value, note: note, image: jpegData))
        saveAndReload(context)
        clearEstimate()
    }

    func updateMeal(_ meal: KoiFoodEntry, value: FoodEstimateValue, note: String, jpegData: Data?) {
        meal.name = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.loggedAt = selectedDate
        meal.calories = finite(value.calories)
        meal.proteinGrams = finite(value.proteinGrams)
        meal.carbohydrateGrams = finite(value.carbohydrateGrams)
        meal.fatGrams = finite(value.fatGrams)
        meal.fiberGrams = finite(value.fiberGrams)
        meal.addedSugarGrams = finite(value.addedSugarGrams)
        meal.sodiumMilligrams = finite(value.sodiumMilligrams)
        meal.confidence = min(max(value.confidence, 0), 1)
        meal.imageJPEG = jpegData
        meal.notes = note
        if let context { saveAndReload(context) }
    }

    func deleteMeal(_ meal: KoiFoodEntry) {
        guard let context else { return }
        context.delete(meal)
        saveAndReload(context)
    }

    func refineMeal(_ meal: KoiFoodEntry, detail: String, using estimator: any FoodEstimating) async -> FoodEstimateValue? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let savedNote = meal.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = savedNote.isEmpty ? meal.name.trimmingCharacters(in: .whitespacesAndNewlines) : savedNote
        let text = "\(source). More detail: \(trimmed)"
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }
        do {
            return try await estimator.estimate(text: text, jpegData: meal.imageJPEG)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't re-estimate this meal."
            return nil
        } catch {
            errorMessage = "Couldn't re-estimate this meal."
            return nil
        }
    }

    private var totals: [String: Double] {
        NutritionEngine.totals(meals: mealInputs, adjustments: adjustmentInputs)
    }

    private var mealInputs: [MealNutritionInput] {
        meals.map { MealNutritionInput(calories: $0.calories, protein: $0.proteinGrams, carbs: $0.carbohydrateGrams, fat: $0.fatGrams, fiber: $0.fiberGrams, addedSugar: $0.addedSugarGrams, sodium: $0.sodiumMilligrams) }
    }

    private var adjustmentInputs: [NutritionAdjustmentInput] {
        manualEntries.map { NutritionAdjustmentInput(key: $0.nutrientKey, value: $0.value) }
    }

    private func mealTotal(for key: String) -> Double {
        switch key {
        case "calories": meals.reduce(0) { $0 + $1.calories }
        case "protein": meals.reduce(0) { $0 + $1.proteinGrams }
        case "carbs": meals.reduce(0) { $0 + $1.carbohydrateGrams }
        case "fat": meals.reduce(0) { $0 + $1.fatGrams }
        case "fiber": meals.reduce(0) { $0 + $1.fiberGrams }
        case "added_sugar": meals.reduce(0) { $0 + $1.addedSugarGrams }
        case "sodium": meals.reduce(0) { $0 + $1.sodiumMilligrams }
        default: 0
        }
    }

    private func createManualEntry(_ key: String, in context: ModelContext) -> KoiNutrientEntry? {
        guard goals.contains(where: { $0.key == key }) else { return nil }
        let entry = KoiNutrientEntry(date: selectedDate, nutrientKey: key)
        context.insert(entry)
        manualEntries.append(entry)
        return entry
    }

    private func makeFoodEntry(_ value: FoodEstimateValue, note: String, image: Data?) -> KoiFoodEntry {
        let name = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? note.trimmingCharacters(in: .whitespacesAndNewlines) : name
        return KoiFoodEntry(
            name: displayName.isEmpty ? "Meal" : displayName,
            loggedAt: selectedDate,
            calories: finite(value.calories),
            proteinGrams: finite(value.proteinGrams),
            carbohydrateGrams: finite(value.carbohydrateGrams),
            fatGrams: finite(value.fatGrams),
            fiberGrams: finite(value.fiberGrams),
            addedSugarGrams: finite(value.addedSugarGrams),
            sodiumMilligrams: finite(value.sodiumMilligrams),
            confidence: value.confidence,
            imageJPEG: image,
            notes: note
        )
    }

    private func saveAndReload(_ context: ModelContext) {
        do { try context.save(); load(context); toast = nil }
        catch { logger.error("Unable to save Intake changes."); errorMessage = "Couldn't save that nutrition change. Try again." }
    }

    private func finite(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }

    private static func dayIdentifier(for date: Date, calendar input: Calendar) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func slug(_ input: String) -> String {
        let ascii = input.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let pieces = ascii.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return pieces.isEmpty ? UUID().uuidString.lowercased() : pieces.joined(separator: "_")
    }

    private static func sortGoals(_ lhs: KoiNutrientGoal, _ rhs: KoiNutrientGoal) -> Bool {
        let order = ["calories", "protein", "fiber", "water"]
        let left = order.firstIndex(of: lhs.key) ?? (order.count + (lhs.isActive ? 0 : 10))
        let right = order.firstIndex(of: rhs.key) ?? (order.count + (rhs.isActive ? 0 : 10))
        return left == right ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : left < right
    }

    private static let defaultGoals: [(key: String, name: String, unit: String, goal: Double, step: Double, type: NutrientGoalType)] = [
        ("calories", "Calories", "kcal", 2_200, 50, .around),
        ("protein", "Protein", "g", 140, 5, .reach),
        ("fiber", "Fiber", "g", 30, 1, .reach),
        ("water", "Water", "oz", 100, 8, .reach)
    ]

    private static let availablePresets: [(key: String, name: String, unit: String, goal: Double, step: Double, type: NutrientGoalType)] = [
        ("added_sugar", "Added sugar", "g", 36, 1, .limit),
        ("carbs", "Carbs", "g", 250, 5, .limit),
        ("fat", "Fat", "g", 70, 5, .track),
        ("sodium", "Sodium", "mg", 2_300, 50, .limit)
    ]
}
