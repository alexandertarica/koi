import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

struct MovementDaySummary: Identifiable {
    let date: Date
    let steps: Int
    let didTrain: Bool
    var id: Date { date }
    var dayLetter: String { date.formatted(.dateTime.weekday(.narrow)) }
}

@MainActor
@Observable
final class MovementViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Movement")
    private let calendar: Calendar
    private var context: ModelContext?
    private var goal: KoiMovementGoal?
    private var movementDays: [KoiMovementDay] = []

    private(set) var selectedDate: Date
    private(set) var stepGoal = 8_000
    private(set) var weeklyWorkoutGoal = 4
    private(set) var steps = 0
    private(set) var isManuallyTrained = false
    private(set) var workoutsThisWeek = 0
    private(set) var averageSteps = 0
    private(set) var bestDaySteps = 0
    private(set) var week: [MovementDaySummary] = []
    private(set) var healthEnabled = false
    private(set) var isRefreshingHealth = false
    private(set) var errorMessage: String?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: .now)
    }

    var stepScore: Double { min(Double(max(steps, 0)) / Double(max(stepGoal, 1)), 1) }
    var trainingScore: Double {
        ExerciseEngine.score(ExerciseDayInput(steps: steps, stepGoal: stepGoal, isTrainingDay: isTrainingDay, workoutsInLastSevenDays: workoutsThisWeek, weeklyWorkoutGoal: weeklyWorkoutGoal)).trainingScore
    }
    var exerciseScore: Double {
        ExerciseEngine.score(ExerciseDayInput(steps: steps, stepGoal: stepGoal, isTrainingDay: isTrainingDay, workoutsInLastSevenDays: workoutsThisWeek, weeklyWorkoutGoal: weeklyWorkoutGoal)).score
    }
    var isTrainingDay: Bool { isManuallyTrained || ((day(for: selectedDate)?.healthWorkoutCount ?? 0) > 0) }
    var stepSourceLabel: String { day(for: selectedDate)?.healthSteps == nil ? "Steps" : "Steps · Health" }
    var stepsRemaining: Int { max(stepGoal - steps, 0) }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            let fetchedGoals = try context.fetch(FetchDescriptor<KoiMovementGoal>())
            if let stored = fetchedGoals.first(where: { $0.id == "movement" }) {
                goal = stored
            } else {
                let created = KoiMovementGoal()
                context.insert(created)
                try context.save()
                goal = created
            }
            stepGoal = max(goal?.stepGoal ?? 8_000, 1)
            weeklyWorkoutGoal = max(goal?.weeklyWorkoutGoal ?? 4, 1)
            healthEnabled = goal?.healthEnabled ?? false
            movementDays = try context.fetch(FetchDescriptor<KoiMovementDay>(sortBy: [SortDescriptor(\.date)]))
            updateDerivedState()
        } catch {
            logger.error("Unable to load Movement data.")
            errorMessage = "Couldn't load today's movement. Try again."
        }
    }

    func changeSteps(by delta: Int) {
        guard let context else { return }
        let record = day(for: selectedDate) ?? createDay(in: context)
        record.manualStepAdjustment = min(max(record.manualStepAdjustment + delta, -max(record.healthSteps ?? 0, 0)), 1_000_000)
        saveAndReload(context)
    }

    func setStepGoal(_ value: Int) {
        guard let context, let goal, (1_000...30_000).contains(value) else { return }
        goal.stepGoal = value
        saveAndReload(context)
    }

    func setWeeklyWorkoutGoal(_ value: Int) {
        guard let context, let goal, (1...14).contains(value) else { return }
        goal.weeklyWorkoutGoal = value
        saveAndReload(context)
    }

    func clearError() { errorMessage = nil }

    func toggleManualTraining() {
        guard let context else { return }
        let record = day(for: selectedDate) ?? createDay(in: context)
        record.didManuallyTrain.toggle()
        saveAndReload(context)
    }

    func connectHealth(using provider: any HealthProviding) async {
        guard provider.isAvailable else {
            errorMessage = HealthServiceError.unavailable.localizedDescription
            return
        }
        isRefreshingHealth = true
        errorMessage = nil
        defer { isRefreshingHealth = false }
        do {
            try await provider.requestReadAccess()
            if let goal { goal.healthEnabled = true }
            healthEnabled = true
            if let context { try context.save() }
            await refreshHealth(using: provider)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't connect Apple Health. Try again."
        } catch {
            logger.error("Health connection failed.")
            errorMessage = "Couldn't connect Apple Health. Try again."
        }
    }

    func refreshHealth(using provider: any HealthProviding) async {
        guard healthEnabled, provider.isAvailable else { return }
        guard let context else { return }
        isRefreshingHealth = true
        defer { isRefreshingHealth = false }
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        do {
            let samples = try await provider.movementData(from: start, to: end, calendar: calendar)
            for sample in samples {
                let record = movementDays.first(where: { calendar.isDate($0.date, inSameDayAs: sample.date) }) ?? createDay(for: sample.date, in: context)
                record.healthSteps = max(sample.steps, 0)
                record.healthWorkoutCount = max(sample.workoutCount, 0)
            }
            try context.save()
            load(context)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't refresh Apple Health. Try again."
        } catch {
            logger.error("Health refresh failed.")
            errorMessage = "Couldn't refresh Apple Health. Try again."
        }
    }

    private func updateDerivedState() {
        let today = calendar.startOfDay(for: selectedDate)
        let days = (0..<7).compactMap { offset -> KoiMovementDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return movementDays.first { calendar.isDate($0.date, inSameDayAs: date) }
        }
        let todayRecord = movementDays.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        steps = todayRecord?.steps ?? 0
        isManuallyTrained = todayRecord?.didManuallyTrain ?? false
        workoutsThisWeek = days.reduce(0) { $0 + $1.workoutCount }
        let stepValues = days.map(\.steps)
        averageSteps = stepValues.isEmpty ? 0 : stepValues.reduce(0, +) / stepValues.count
        bestDaySteps = stepValues.max() ?? 0
        week = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            let item = movementDays.first { calendar.isDate($0.date, inSameDayAs: date) }
            return MovementDaySummary(date: date, steps: item?.steps ?? 0, didTrain: item?.isTrainingDay ?? false)
        }
    }

    private func day(for date: Date) -> KoiMovementDay? {
        movementDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func createDay(in context: ModelContext) -> KoiMovementDay { createDay(for: selectedDate, in: context) }

    private func createDay(for date: Date, in context: ModelContext) -> KoiMovementDay {
        let created = KoiMovementDay(date: calendar.startOfDay(for: date))
        context.insert(created)
        movementDays.append(created)
        return created
    }

    private func saveAndReload(_ context: ModelContext) {
        do { try context.save(); load(context) }
        catch {
            logger.error("Unable to save Movement changes.")
            errorMessage = "Couldn't save that movement change. Try again."
        }
    }
}
