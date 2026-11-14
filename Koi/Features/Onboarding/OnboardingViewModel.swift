import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI
import KoiShared

enum OnboardingStep: Int, CaseIterable {
    case welcome, name, focus, habits, about, connect, ready

    var title: String {
        switch self {
        case .welcome: "A steadier day"
        case .name: "What should Koi call you?"
        case .focus: "Your focus"
        case .habits: "A few small rituals"
        case .about: "About you"
        case .connect: "Bring your day together"
        case .ready: "Your water, your pace"
        }
    }

    var detail: String {
        switch self {
        case .welcome: "Habits, food and movement in one calm place."
        case .name: "A name makes each day feel like yours."
        case .focus: "Every part of your day still counts."
        case .habits: "Start with three things you would like to return to."
        case .about: "Optional details help Koi suggest a gentle starting point."
        case .connect: "You can connect Apple Health and Calendar from their screens."
        case .ready: "Small steps add up. Koi is here when you are."
        }
    }
}

struct OnboardingHabitDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var isSelected = true
}

@MainActor
@Observable
final class OnboardingViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Onboarding")
    private var context: ModelContext?
    private var state: KoiOnboardingState?
    private(set) var step: OnboardingStep = .welcome
    private(set) var isCompleted = false
    private(set) var shouldShowTour = false
    private(set) var errorMessage: String?
    var name = ""
    var focus: BalanceFocus = .allRounder
    var habits = [OnboardingHabitDraft(title: "Make the bed"), OnboardingHabitDraft(title: "Read a little"), OnboardingHabitDraft(title: "Take a walk")]
    var birthYear = Calendar.current.component(.year, from: .now) - 30
    var heightCM = 170.0
    var startingWeightLB = 150.0
    var sexAtBirth = "Prefer not to say"
    var stepGoal = 8_000
    var weeklyWorkoutGoal = 4
    var notificationMode = "smart"
        var dailyCheckInHour = 9
    var betaEmail = ""
    var launchEmail = ""
    var sendsBetaEmail = false
    var sendsLaunchEmail = false
    var hasAboutDetails = false
    var wantsHealth = false
    var wantsCalendar = false

    var progress: Double { Double(step.rawValue + 1) / Double(OnboardingStep.allCases.count) }
    var canContinue: Bool {
        switch step {
        case .name:
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!sendsBetaEmail || isValidEmail(betaEmail))
        case .habits: habits.filter { $0.isSelected && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 3
        case .ready: !sendsLaunchEmail || isValidEmail(launchEmail)
        default: true
        }
    }
    var selectedHabitCount: Int { habits.filter(\.isSelected).count }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            state = try context.fetch(FetchDescriptor<KoiOnboardingState>()).first
            isCompleted = state?.isComplete ?? false
            shouldShowTour = isCompleted && !(state?.hasSeenTour ?? false)
        } catch {
            logger.error("Unable to load onboarding state.")
            errorMessage = "Couldn't open setup. Try again."
        }
    }

    func advance() {
        guard canContinue else { return }
        guard step == .ready else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready }
            return
        }
        finish()
    }

    func goBack() {
        guard step.rawValue > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
    }

    func skipToDefaults() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Friend" : name
        focus = .allRounder
        habits = ["Make the bed", "Read a little", "Take a walk"].map { OnboardingHabitDraft(title: $0) }
        stepGoal = 8_000
        weeklyWorkoutGoal = 4
        notificationMode = "smart"
        finish()
    }

    func skipQuickSetup() {
        name = ""
        focus = .allRounder
        habits = []
        wantsHealth = false
        wantsCalendar = false
        stepGoal = 8_000
        weeklyWorkoutGoal = 4
        finish(offerTour: false)
    }

    func finishQuickSetup() {
        habits = []
        stepGoal = 8_000
        weeklyWorkoutGoal = 4
        notificationMode = "none"
        finish(offerTour: false)
    }

    func toggleHabit(_ id: UUID) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].isSelected.toggle()
    }

    func setHabitTitle(_ id: UUID, title: String) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].title = title
    }

    func finish(offerTour: Bool = true) {
        guard let context else { return }
        do {
            let profile = try context.fetch(FetchDescriptor<KoiProfile>()).first ?? KoiProfile()
            if profile.modelContext == nil { context.insert(profile) }
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.name = cleanName.isEmpty ? "Friend" : String(cleanName.prefix(40))
            profile.focusKey = focus.rawValue

            let selected = habits.filter { $0.isSelected }.compactMap { draft -> String? in
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : String(title.prefix(60))
            }
            let storedHabits = try context.fetch(FetchDescriptor<KoiHabit>())
            let existingTitles = Set(storedHabits.map { $0.title.localizedLowercase })
            for title in selected where !existingTitles.contains(title.localizedLowercase) {
                context.insert(KoiHabit(title: title))
            }

            let movement = try context.fetch(FetchDescriptor<KoiMovementGoal>()).first ?? KoiMovementGoal()
            if movement.modelContext == nil { context.insert(movement) }
            movement.stepGoal = min(max(stepGoal, 1_000), 30_000)
            movement.weeklyWorkoutGoal = min(max(weeklyWorkoutGoal, 1), 14)
            movement.healthEnabled = wantsHealth

            var byKey = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<KoiNutrientGoal>()).map { ($0.key, $0) })
            let defaults: [(String, String, String, Double, Double, String)] = [("calories", "Calories", "kcal", 2_200, 50, "around"), ("protein", "Protein", "g", 140, 5, "reach"), ("fiber", "Fiber", "g", 30, 1, "reach"), ("water", "Water", "oz", 100, 8, "reach")]
            for (key, label, unit, value, step, type) in defaults where byKey[key] == nil {
                let goal = KoiNutrientGoal(key: key, name: label, unit: unit, goal: value, step: step, goalType: type)
                context.insert(goal)
                byKey[key] = goal
            }

            if hasAboutDetails, startingWeightLB.isFinite, startingWeightLB >= 50, startingWeightLB <= 600,
               try context.fetch(FetchDescriptor<KoiBodyWeightEntry>()).isEmpty {
                context.insert(KoiBodyWeightEntry(weightLB: startingWeightLB))
            }

            let storedState = state ?? KoiOnboardingState()
            if storedState.modelContext == nil { context.insert(storedState) }
            storedState.isComplete = true
            storedState.birthYear = hasAboutDetails ? birthYear : nil
            storedState.heightCM = hasAboutDetails ? heightCM : nil
            storedState.sexAtBirth = hasAboutDetails ? sexAtBirth : nil
            storedState.healthConnected = wantsHealth
            storedState.calendarConnected = wantsCalendar
            storedState.notificationMode = notificationMode
            storedState.dailyCheckInHour = min(max(dailyCheckInHour, 8), 20)
            storedState.betaEmail = sendsBetaEmail ? betaEmail.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            storedState.launchEmail = sendsLaunchEmail ? launchEmail.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            try context.save()
            state = storedState
            isCompleted = true
            shouldShowTour = offerTour
        } catch {
            logger.error("Unable to save onboarding choices.")
            errorMessage = "Couldn't save your setup. Try again."
        }
    }

    func markTourSeen() {
        guard let context, let state else { return }
        state.hasSeenTour = true
        do { try context.save(); shouldShowTour = false }
        catch { logger.error("Unable to save tour state.") }
    }

    func clearError() { errorMessage = nil }

    private func isValidEmail(_ value: String) -> Bool {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].split(separator: ".", omittingEmptySubsequences: false).count >= 2
            && parts[1].split(separator: ".").allSatisfy { !$0.isEmpty }
    }
}
