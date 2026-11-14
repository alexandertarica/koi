import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

@MainActor
@Observable
final class ProfileViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Profile")
    private let calendar: Calendar
    private var context: ModelContext?
    private(set) var profile: KoiProfile?
    private(set) var weightEntries: [KoiBodyWeightEntry] = []
    private(set) var nutrientGoals: [KoiNutrientGoal] = []
    private(set) var movementGoal: KoiMovementGoal?
    private(set) var errorMessage: String?
    private(set) var savedWeight: Double?
    var weightDraft = 150.0
    var nameDraft = "Friend"

    init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    var focus: BalanceFocus { BalanceFocus(rawValue: profile?.focusKey ?? "") ?? .allRounder }
    var hasWeightToday: Bool { weightEntries.contains { calendar.isDateInToday($0.date) } }
    var currentWeight: Double? { weightEntries.last?.weightLB }
    var weightTrendText: String {
        guard weightEntries.count > 1 else { return "A steady place to begin." }
        let recent = weightEntries.last?.weightLB ?? 0
        let previous = weightEntries.dropLast().last?.weightLB ?? recent
        let change = recent - previous
        if abs(change) < 0.1 { return "Holding steady." }
        return "\(change > 0 ? "Up" : "Down") \(String(format: "%.1f", abs(change))) lb since your last entry."
    }
    var weightChart: [KoiBodyWeightEntry] { Array(weightEntries.suffix(12)) }
    var nutritionGoalSummary: String {
        let active = nutrientGoals.filter(\.isActive)
        guard !active.isEmpty else { return "Set daily targets in Intake." }
        return active.prefix(3).map { "\($0.name) \(Int($0.goal)) \($0.unit)" }.joined(separator: " · ")
    }
    var exerciseGoalSummary: String {
        "\(movementGoal?.stepGoal ?? 8_000) steps · \(movementGoal?.weeklyWorkoutGoal ?? 4) workouts a week"
    }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            if let stored = try context.fetch(FetchDescriptor<KoiProfile>()).first { profile = stored }
            else {
                let created = KoiProfile()
                context.insert(created)
                try context.save()
                profile = created
            }
            weightEntries = try context.fetch(FetchDescriptor<KoiBodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))
            nutrientGoals = try context.fetch(FetchDescriptor<KoiNutrientGoal>())
            movementGoal = try context.fetch(FetchDescriptor<KoiMovementGoal>()).first
            nameDraft = profile?.name ?? "Friend"
            weightDraft = weightEntries.first(where: { calendar.isDateInToday($0.date) })?.weightLB ?? weightEntries.last?.weightLB ?? 150
            savedWeight = weightEntries.first(where: { calendar.isDateInToday($0.date) })?.weightLB
        } catch {
            logger.error("Unable to load Profile data.")
            errorMessage = "Couldn't load your profile. Try again."
        }
    }

    func saveName() {
        guard let profile else { return }
        let clean = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { nameDraft = profile.name; return }
        profile.name = String(clean.prefix(40))
        nameDraft = profile.name
        persist("profile name")
    }

    func setFocus(_ focus: BalanceFocus) {
        profile?.focusKey = focus.rawValue
        persist("focus")
    }

    func setAvatar(_ data: Data?) {
        guard let profile else { return }
        profile.avatarJPEG = data
        persist("avatar")
    }

    func setWeight(_ value: Double) {
        guard value.isFinite else { return }
        weightDraft = min(max(value, 50), 600)
    }

    func saveWeightToday() {
        guard let context else { return }
        if let entry = weightEntries.first(where: { calendar.isDateInToday($0.date) }) {
            entry.weightLB = weightDraft
        } else {
            let entry = KoiBodyWeightEntry(date: .now, weightLB: weightDraft)
            context.insert(entry)
        }
        do {
            try context.save()
            weightEntries = try context.fetch(FetchDescriptor<KoiBodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))
            savedWeight = weightDraft
        } catch {
            logger.error("Unable to save body weight.")
            errorMessage = "Couldn't save today's weight. Try again."
        }
    }

    func setMovementGoals(steps: Int? = nil, weeklyWorkouts: Int? = nil) {
        guard let context else { return }
        if let movementGoal {
            if let steps { movementGoal.stepGoal = min(max(steps, 1_000), 30_000) }
            if let weeklyWorkouts { movementGoal.weeklyWorkoutGoal = min(max(weeklyWorkouts, 1), 14) }
        } else {
            let created = KoiMovementGoal(stepGoal: steps ?? 8_000, weeklyWorkoutGoal: weeklyWorkouts ?? 4)
            context.insert(created)
            movementGoal = created
        }
        persist("movement goals")
    }

    func clearError() { errorMessage = nil }

    private func persist(_ field: String) {
        guard let context else { return }
        do { try context.save() }
        catch {
            logger.error("Unable to save Profile \(field, privacy: .public).")
            errorMessage = "Couldn't save that change. Try again."
        }
    }
}
