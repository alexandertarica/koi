import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared
import UserNotifications

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
    private(set) var onboardingState: KoiOnboardingState?
    private(set) var notificationMode: KoiNotificationMode = .smart
    private(set) var dailyCheckInHour = 9
    private(set) var calendarConnected = false
    private(set) var healthConnected = false
    private(set) var isUpdatingIntegrations = false
    private(set) var backupEnabled = true
    private(set) var lastBackupAt: Date?
    private(set) var isBackingUp = false
    private(set) var backupMessage: String?
    private(set) var errorMessage: String?
    private(set) var savedWeight: Double?
    var weightDraft = 150.0
    var nameDraft = "Friend"

    init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    var focus: BalanceFocus { BalanceFocus(rawValue: profile?.focusKey ?? "") ?? .allRounder }
    var hasWeightToday: Bool { weightEntries.contains { calendar.isDateInToday($0.date) } }
    var currentWeight: Double? { weightEntries.last?.weightLB }
    var previousWeight: Double? { weightEntries.last(where: { !calendar.isDateInToday($0.date) })?.weightLB }
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
            onboardingState = try context.fetch(FetchDescriptor<KoiOnboardingState>()).first
            notificationMode = KoiNotificationMode(rawValue: onboardingState?.notificationMode ?? "smart") ?? .smart
            dailyCheckInHour = onboardingState?.dailyCheckInHour ?? 9
            calendarConnected = onboardingState?.calendarConnected ?? false
            healthConnected = onboardingState?.healthConnected ?? false
            backupEnabled = onboardingState?.backupEnabled ?? true
            lastBackupAt = onboardingState?.lastBackupAt
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

    func deleteWeight(_ entry: KoiBodyWeightEntry) {
        guard let context else { return }
        context.delete(entry)
        do {
            try context.save()
            weightEntries = try context.fetch(FetchDescriptor<KoiBodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))
            weightDraft = weightEntries.first(where: { calendar.isDateInToday($0.date) })?.weightLB ?? weightEntries.last?.weightLB ?? 150
            savedWeight = weightEntries.first(where: { calendar.isDateInToday($0.date) })?.weightLB
        } catch {
            logger.error("Unable to delete body weight entry.")
            errorMessage = "Couldn't remove that weigh-in. Try again."
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

    func setNotifications(_ mode: KoiNotificationMode, hour: Int, provider: any NotificationProviding) async {
        guard let context else { return }
        isUpdatingIntegrations = true
        defer { isUpdatingIntegrations = false }
        if mode != .none {
            do {
                let status = await provider.authorizationStatus()
                if status == .notDetermined {
                    guard try await provider.requestAuthorization() else {
                        errorMessage = "Allow Koi to send reminders in Settings."
                        return
                    }
                } else if status != .authorized && status != .provisional {
                    errorMessage = "Allow Koi to send reminders in Settings."
                    return
                }
            } catch {
                errorMessage = "Couldn't update reminders. Try again."
                return
            }
        }
        let state = ensureOnboardingState(in: context)
        state.notificationMode = mode.rawValue
        state.dailyCheckInHour = min(max(hour, 8), 20)
        do {
            try context.save()
            notificationMode = mode
            dailyCheckInHour = state.dailyCheckInHour
            let reminders = try makeReminders(mode: mode, context: context)
            let checkIns = mode == .none ? [] : NotificationPlanner.checkIns(hour: state.dailyCheckInHour, now: .now, calendar: calendar)
            try await provider.replaceScheduledReminders(Array((reminders + checkIns).prefix(60)), dailyCheckInHour: nil)
        } catch {
            logger.error("Unable to update notification settings.")
            errorMessage = "Couldn't update reminders. Try again."
        }
    }

    func connectCalendar(using provider: any CalendarProviding) async {
        guard let context else { return }
        isUpdatingIntegrations = true
        defer { isUpdatingIntegrations = false }
        do {
            try await provider.requestAccess()
            let state = ensureOnboardingState(in: context)
            state.calendarConnected = true
            try context.save()
            calendarConnected = true
            let tasks = try context.fetch(FetchDescriptor<KoiTask>()).filter { !$0.isComplete && $0.archivedAt == nil && $0.hasTime && $0.dueAt != nil }
            for task in tasks {
                guard let start = task.dueAt else { continue }
                task.calendarEventID = try await provider.saveTaskEvent(CalendarTaskValue(id: task.id, title: task.title, notes: task.notes, start: start, durationMinutes: task.timeMinutes, eventIdentifier: task.calendarEventID))
            }
            try context.save()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't connect Apple Calendar. Try again."
        } catch {
            logger.error("Unable to connect Calendar.")
            errorMessage = "Couldn't connect Apple Calendar. Try again."
        }
    }

    func disconnectCalendar() {
        guard let context else { return }
        let state = ensureOnboardingState(in: context)
        state.calendarConnected = false
        do { try context.save(); calendarConnected = false }
        catch { logger.error("Unable to update Calendar settings.") }
    }

    func setBackupEnabled(_ enabled: Bool) {
        guard let context else { return }
        let state = ensureOnboardingState(in: context)
        state.backupEnabled = enabled
        do { try context.save(); backupEnabled = enabled }
        catch { logger.error("Unable to update iCloud backup settings."); errorMessage = "Couldn't update backup settings. Try again." }
    }

    func createBackup(using provider: any BackupProviding) async {
        guard let context else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            let date = try await provider.backup(using: context)
            let state = ensureOnboardingState(in: context)
            state.lastBackupAt = date
            try context.save()
            lastBackupAt = date
            backupMessage = "Your private iCloud backup is up to date."
        } catch let error as LocalizedError {
            backupMessage = error.errorDescription ?? "Couldn't back up Koi. Try again."
        } catch {
            logger.error("Unable to create iCloud backup.")
            backupMessage = "Couldn't back up Koi. Try again."
        }
    }

    func restoreBackup(using provider: any BackupProviding) async {
        guard let context else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            let date = try await provider.restore(using: context)
            let state = try context.fetch(FetchDescriptor<KoiOnboardingState>()).first ?? KoiOnboardingState(isComplete: true)
            if state.modelContext == nil { context.insert(state) }
            state.lastBackupAt = date
            state.backupEnabled = true
            try context.save()
            lastBackupAt = date
            backupEnabled = true
            load(context)
            backupMessage = "Koi restored from \(date.formatted(date: .abbreviated, time: .shortened))."
        } catch let error as LocalizedError {
            backupMessage = error.errorDescription ?? "Couldn't restore Koi. Try again."
        } catch {
            logger.error("Unable to restore iCloud backup.")
            backupMessage = "Couldn't restore Koi. Try again."
        }
    }

    func clearBackupMessage() { backupMessage = nil }

    private func ensureOnboardingState(in context: ModelContext) -> KoiOnboardingState {
        if let onboardingState { return onboardingState }
        let created = KoiOnboardingState(isComplete: true)
        context.insert(created)
        onboardingState = created
        return created
    }

    private func makeReminders(mode: KoiNotificationMode, context: ModelContext) throws -> [NotificationReminder] {
        guard mode == .smart else { return [] }
        var reminders: [NotificationReminder] = []
        let habits = try context.fetch(FetchDescriptor<KoiHabit>()).filter { $0.isActive && $0.pausedAt == nil && $0.reminderTime != nil }
        let logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
        reminders += NotificationPlanner.habitReminders(habits: habits, logs: logs, now: .now, calendar: calendar)
        let tasks = try context.fetch(FetchDescriptor<KoiTask>()).filter { !$0.isComplete && $0.archivedAt == nil && $0.hasTime && $0.dueAt != nil && $0.timeMinutes > 0 }
        for task in tasks {
            guard let dueAt = task.dueAt else { continue }
            let reminderAt = dueAt.addingTimeInterval(-10 * 60)
            if reminderAt > .now {
                reminders.append(NotificationReminder(id: "task-\(task.id.uuidString)", title: "In 10 minutes, \(task.title).", date: reminderAt, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "Coming up", tab: 1))
            }
        }
        return Array(reminders.prefix(60))
    }

    private func persist(_ field: String) {
        guard let context else { return }
        do { try context.save() }
        catch {
            logger.error("Unable to save Profile \(field, privacy: .public).")
            errorMessage = "Couldn't save that change. Try again."
        }
    }
}
