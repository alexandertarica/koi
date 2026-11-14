import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

struct WorkoutJournalStats: Equatable {
    let workouts: Int
    let sets: Int
    let volumeLB: Int
}

struct WorkoutCompletionSummary: Equatable, Identifiable {
    let id: UUID
    let name: String
    let minutes: Int
    let sets: Int
    let volumeLB: Int
    let bestLifts: [String]
}

struct WorkoutLiftHistory: Identifiable {
    let name: String
    let group: String
    let best: String
    let lastSession: String
    var id: String { name.lowercased() }
}

@MainActor
@Observable
final class WorkoutViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Workout")
    private let calendar: Calendar
    private var context: ModelContext?
    private var sessions: [KoiWorkoutSession] = []
    private var routineLifts: [KoiRoutineLift] = []
    private var workoutLifts: [KoiWorkoutLift] = []
    private var workoutSets: [KoiWorkoutSet] = []
    private var movementDays: [KoiMovementDay] = []

    private(set) var routines: [KoiWorkoutRoutine] = []
    private(set) var activeSession: KoiWorkoutSession?
    private(set) var selectedLiftID: UUID?
    private(set) var editingSetID: UUID?
    private(set) var currentWeight = 45.0
    private(set) var currentReps = 8
    private(set) var lastContext = ""
    private(set) var isNewBest = false
    private(set) var errorMessage: String?
    private(set) var completionSummary: WorkoutCompletionSummary?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    var activeLifts: [KoiWorkoutLift] {
        guard let activeSession else { return [] }
        return workoutLifts.filter { $0.sessionID == activeSession.id }.sorted { $0.order < $1.order }
    }
    var currentLift: KoiWorkoutLift? { activeLifts.first(where: { $0.id == selectedLiftID }) ?? activeLifts.first }
    var currentSets: [KoiWorkoutSet] {
        guard let lift = currentLift, let activeSession else { return [] }
        return workoutSets.filter { $0.sessionID == activeSession.id && $0.liftID == lift.id }.sorted { $0.loggedAt < $1.loggedAt }
    }
    func setCount(for lift: KoiWorkoutLift) -> Int {
        guard let activeSession else { return 0 }
        return workoutSets.filter { $0.sessionID == activeSession.id && $0.liftID == lift.id && !$0.isWarmUp }.count
    }
    func routineLiftNames(_ routine: KoiWorkoutRoutine) -> [String] {
        routineLifts.filter { $0.routineID == routine.id }.sorted { $0.order < $1.order }.map(\.name)
    }
    var restSecondsRemaining: Int {
        guard let restUntil = activeSession?.restUntil else { return 0 }
        return max(Int(ceil(restUntil.timeIntervalSinceNow)), 0)
    }
    var isResting: Bool { restSecondsRemaining > 0 }
    var isEditingSet: Bool { editingSetID != nil }
    var isCurrentLiftBodyweight: Bool { currentLift.map { WorkoutNameRules.isBodyweight($0.name) } ?? false }
    var completedWorkouts: [KoiWorkoutSession] {
        sessions.filter(\.isComplete).sorted { $0.startedAt > $1.startedAt }
    }
    var routinesByName: [KoiWorkoutRoutine] { routines.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var plannedRoutines: [KoiWorkoutRoutine] { routines.filter { $0.plannedAt.map { calendar.isDateInToday($0) || calendar.isDateInTomorrow($0) } ?? false }.sorted { ($0.plannedAt ?? .distantFuture) < ($1.plannedAt ?? .distantFuture) } }
    var todaysPlannedRoutine: KoiWorkoutRoutine? { routines.first { $0.plannedAt.map { calendar.isDate($0, inSameDayAs: .now) } ?? false } }

    var recommendation: WorkoutRecommendation {
        let lastByGroup = Dictionary(grouping: completedWorkouts, by: \.muscleGroup).compactMapValues { $0.map(\.startedAt).max() }
        let lastRoutineNames = Dictionary(grouping: completedWorkouts, by: \.muscleGroup).compactMapValues { sessions in
            sessions.sorted { $0.startedAt > $1.startedAt }.first?.name
        }
        let summaries = routines.map { WorkoutRoutineSummary(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, plannedAt: $0.plannedAt) }
        let planned = todaysPlannedRoutine.map { WorkoutRoutineSummary(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, plannedAt: $0.plannedAt) }
        return WorkoutEngine.recommend(WorkoutRecommendationInput(groupLastTrained: lastByGroup, lastRoutineNameByGroup: lastRoutineNames, consecutiveTrainingDays: consecutiveTrainingDays, plannedRoutine: planned, routines: summaries))
    }

    var canLogAlreadyDid: Bool {
        guard !recommendation.suggestsRest else { return false }
        return completedWorkouts.contains { $0.muscleGroup == recommendation.group }
    }

    var journalStats: WorkoutJournalStats {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let week = completedWorkouts.filter { $0.startedAt >= start }
        let ids = Set(week.map(\.id))
        let sets = workoutSets.filter { ids.contains($0.sessionID) && !$0.isWarmUp }
        return WorkoutJournalStats(workouts: week.count, sets: sets.count, volumeLB: Int(sets.reduce(0) { $0 + $1.weightLB * Double($1.reps) }.rounded()))
    }

    var pastWorkouts: [KoiWorkoutSession] {
        let start = calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: .now)) ?? .distantPast
        return completedWorkouts.filter { $0.startedAt >= start }.prefix(5).map { $0 }
    }
    var liftHistory: [WorkoutLiftHistory] {
        let completedIDs = Set(completedWorkouts.map(\.id))
        let grouped = Dictionary(grouping: workoutLifts.filter { completedIDs.contains($0.sessionID) }, by: { $0.name.lowercased() })
        return grouped.values.compactMap { lifts in
            guard let lift = lifts.first else { return nil }
            let ids = Set(lifts.map(\.id))
            let sets = workoutSets.filter { ids.contains($0.liftID) && !$0.isWarmUp }
            guard !sets.isEmpty else { return nil }
            let best = sets.compactMap { WorkoutEngine.estimatedOneRepMax(weightLB: $0.weightLB, reps: $0.reps, isBodyweight: $0.isBodyweight) }.max()
            let latest = sets.max(by: { $0.loggedAt < $1.loggedAt })
            let bestText = best.map { "\(Int($0.rounded())) lb est." } ?? "Bodyweight"
            let lastText = latest.map { "\(Int($0.weightLB)) × \($0.reps)" } ?? ""
            return WorkoutLiftHistory(name: lift.name, group: lift.muscleGroup, best: bestText, lastSession: lastText)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var suggestedNextLifts: [String] {
        let names: [String]
        switch currentLift?.muscleGroup ?? recommendation.group {
        case "pull": names = ["Chest-supported row", "Lat pulldown", "Dumbbell curl"]
        case "legs": names = ["Goblet squat", "Romanian deadlift", "Leg press"]
        case "core": names = ["Plank", "Dead bug", "Pallof press"]
        default: names = ["Dumbbell bench press", "Shoulder press", "Triceps pushdown"]
        }
        let existing = Set(activeLifts.map { $0.name.lowercased() })
        return names.filter { !existing.contains($0.lowercased()) }
    }

    func load(_ context: ModelContext) {
        self.context = context
        do {
            routines = try context.fetch(FetchDescriptor<KoiWorkoutRoutine>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            routineLifts = try context.fetch(FetchDescriptor<KoiRoutineLift>())
            sessions = try context.fetch(FetchDescriptor<KoiWorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            workoutLifts = try context.fetch(FetchDescriptor<KoiWorkoutLift>())
            workoutSets = try context.fetch(FetchDescriptor<KoiWorkoutSet>(sortBy: [SortDescriptor(\.loggedAt)]))
            movementDays = try context.fetch(FetchDescriptor<KoiMovementDay>())
            activeSession = sessions.first(where: { !$0.isComplete })
            if let activeSession, let selectedLiftID, !activeLifts.contains(where: { $0.id == selectedLiftID }) {
                self.selectedLiftID = activeLifts.first?.id
            } else if selectedLiftID == nil {
                selectedLiftID = activeLifts.first(where: { loggedSetCount(for: $0) < $0.targetSets })?.id ?? activeLifts.first?.id
            }
            if let lift = currentLift { hydrateSet(for: lift) }
        } catch {
            logger.error("Unable to load workout journal.")
            errorMessage = "Couldn't load your workouts. Try again."
        }
    }

    func startEmptyWorkout() { beginSession(name: "Just go", group: recommendation.group, routineID: nil, lifts: []) }

    func startRoutine(_ routine: KoiWorkoutRoutine) {
        let templates = routineLifts.filter { $0.routineID == routine.id }.sorted { $0.order < $1.order }
        let planned = routine.plannedAt.map { calendar.isDateInToday($0) } ?? false
        beginSession(name: routine.name, group: routine.muscleGroup, routineID: routine.id, lifts: templates.map { ($0.name, $0.muscleGroup, $0.targetSets, $0.targetReps, $0.restSeconds) })
        if planned { routine.plannedAt = nil; persist() }
    }

    func startRecommendedWorkout() {
        if let id = recommendation.routine?.id, let routine = routines.first(where: { $0.id == id }) {
            startRoutine(routine)
        } else if recommendation.suggestsRest {
            startEmptyWorkout()
        } else {
            startPreset(recommendation.group)
        }
    }

    func startPreset(_ group: String) {
        let lifts: [(String, String, Int, Int, Int)]
        switch group {
        case "pull": lifts = [("Lat pulldown", "pull", 3, 8, 90), ("Seated row", "pull", 3, 10, 90), ("Dumbbell curl", "pull", 3, 12, 60)]
        case "legs": lifts = [("Goblet squat", "legs", 3, 10, 120), ("Romanian deadlift", "legs", 3, 8, 120), ("Split squat", "legs", 3, 10, 90)]
        case "core": lifts = [("Plank", "core", 3, 30, 60), ("Dead bug", "core", 3, 10, 60), ("Pallof press", "core", 3, 10, 60)]
        default: lifts = [("Dumbbell bench press", "push", 3, 8, 120), ("Shoulder press", "push", 3, 8, 90), ("Triceps pushdown", "push", 3, 12, 60)]
        }
        beginSession(name: "\(group.capitalized) day", group: group, routineID: nil, lifts: lifts)
    }

    func repeatWorkout(_ session: KoiWorkoutSession) {
        let lifts = workoutLifts.filter { $0.sessionID == session.id }.sorted { $0.order < $1.order }
            .map { ($0.name, $0.muscleGroup, $0.targetSets, $0.targetReps, $0.restSeconds) }
        beginSession(name: session.name, group: session.muscleGroup, routineID: session.routineID, lifts: lifts)
    }

    func saveAsRoutine(_ summary: WorkoutCompletionSummary) {
        let lifts = workoutLifts.filter { $0.sessionID == summary.id }.sorted { $0.order < $1.order }.map(\.name)
        saveRoutine(existing: nil, name: summary.name, liftNames: lifts, plannedAt: nil, startNow: false)
    }

    func saveRoutine(existing: KoiWorkoutRoutine?, name: String, liftNames: [String], plannedAt: Date?, startNow: Bool, targetSets: Int = 3, targetReps: Int = 8) {
        guard let context else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = liftNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanName.isEmpty else { errorMessage = "Give this routine a name."; return }
        if let existing {
            for lift in routineLifts where lift.routineID == existing.id { context.delete(lift) }
            existing.name = cleanName
            existing.muscleGroup = WorkoutNameRules.guessRoutineGroup(cleanName)
            existing.plannedAt = startNow ? nil : plannedAt
            for (index, liftName) in names.enumerated() {
                context.insert(KoiRoutineLift(routineID: existing.id, name: liftName, muscleGroup: WorkoutNameRules.guessGroup(liftName), targetSets: targetSets, targetReps: targetReps, order: index))
            }
            do {
                try context.save()
                if startNow { startRoutine(existing) } else { load(context) }
            } catch {
                logger.error("Unable to update a workout routine.")
                errorMessage = "Couldn't save that routine. Try again."
            }
        } else {
            let group = WorkoutNameRules.guessRoutineGroup(cleanName)
            let routine = KoiWorkoutRoutine(name: cleanName, muscleGroup: group, plannedAt: startNow ? nil : plannedAt)
            context.insert(routine)
            for (index, liftName) in names.enumerated() {
                context.insert(KoiRoutineLift(routineID: routine.id, name: liftName, muscleGroup: WorkoutNameRules.guessGroup(liftName), targetSets: targetSets, targetReps: targetReps, order: index))
            }
            do {
                try context.save()
                if startNow { startRoutine(routine) } else { load(context) }
            } catch {
                logger.error("Unable to save a workout routine.")
                errorMessage = "Couldn't save that routine. Try again."
            }
        }
    }

    func deleteRoutine(_ routine: KoiWorkoutRoutine) {
        guard let context else { return }
        for lift in routineLifts where lift.routineID == routine.id { context.delete(lift) }
        context.delete(routine)
        persist()
    }

    func logAlreadyDid() {
        guard !recommendation.suggestsRest,
              let previous = completedWorkouts.first(where: { $0.muscleGroup == recommendation.group }) else { return }
        let priorLifts = workoutLifts.filter { $0.sessionID == previous.id }.sorted { $0.order < $1.order }
        let templates = priorLifts.map { ($0.name, $0.muscleGroup, $0.targetSets, $0.targetReps, $0.restSeconds) }
        beginSession(name: recommendation.routine?.name ?? previous.name, group: recommendation.group, routineID: recommendation.routine?.id, lifts: templates)
        guard let session = activeSession, let context else { return }
        for lift in activeLifts {
            let previousLift = priorLifts.first { $0.name.localizedCaseInsensitiveCompare(lift.name) == .orderedSame }
            guard let previousLift else { continue }
            let previousSets = workoutSets.filter { $0.sessionID == previous.id && $0.liftID == previousLift.id }.sorted { $0.loggedAt < $1.loggedAt }
            for oldSet in previousSets {
                context.insert(KoiWorkoutSet(sessionID: session.id, liftID: lift.id, weightLB: oldSet.weightLB, reps: oldSet.reps, isWarmUp: oldSet.isWarmUp, isBodyweight: oldSet.isBodyweight))
            }
        }
        do { try context.save(); load(context) }
        catch { errorMessage = "Couldn't log that workout. Try again."; return }
        _ = endSession()
    }

    func addLift(name: String) {
        guard let context, let activeSession else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let lift = KoiWorkoutLift(sessionID: activeSession.id, name: cleanName, muscleGroup: WorkoutNameRules.guessGroup(cleanName), order: activeLifts.count)
        context.insert(lift)
        persist()
        selectLift(lift.id)
    }

    func removeLift(_ lift: KoiWorkoutLift) {
        guard let context else { return }
        for set in workoutSets where set.liftID == lift.id { context.delete(set) }
        context.delete(lift)
        if selectedLiftID == lift.id { selectedLiftID = nil }
        persist()
    }

    func selectLift(_ id: UUID) {
        selectedLiftID = id
        isNewBest = false
        if let lift = activeLifts.first(where: { $0.id == id }) { hydrateSet(for: lift) }
    }

    func changeMuscleGroup(of lift: KoiWorkoutLift, to group: String) {
        guard ["push", "pull", "legs", "core", "upper", "lower", "full body"].contains(group) else { return }
        lift.muscleGroup = group
        persist()
    }

    func selectSetForEditing(_ set: KoiWorkoutSet) {
        editingSetID = set.id
        currentWeight = set.isBodyweight ? 0 : set.weightLB
        currentReps = set.reps
    }

    func setWeight(_ value: Double) { currentWeight = value.isFinite ? max(value, 0) : 0 }
    func setReps(_ value: Int) { currentReps = min(max(value, 0), 1_000) }
    func changeWeight(by delta: Double) { setWeight(currentWeight + delta) }
    func changeReps(by delta: Int) { setReps(currentReps + delta) }

    func applyProgression() {
        guard let lift = currentLift, let progression = progression(for: lift) else { return }
        currentWeight = progression.weightLB
        currentReps = progression.reps
    }

    func logSet(isWarmUp: Bool = false) {
        guard let context, let activeSession, let lift = currentLift else { return }
        let bodyweight = WorkoutNameRules.isBodyweight(lift.name)
        let weight = bodyweight ? 0 : currentWeight
        let previousBest = bestOneRepMax(for: lift.name)
        let set: KoiWorkoutSet
        var warmUp = isWarmUp
        if let editingSetID, let existing = workoutSets.first(where: { $0.id == editingSetID }) {
            existing.weightLB = weight
            existing.reps = currentReps
            existing.isBodyweight = bodyweight
            warmUp = existing.isWarmUp
            set = existing
            self.editingSetID = nil
        } else {
            set = KoiWorkoutSet(sessionID: activeSession.id, liftID: lift.id, weightLB: weight, reps: currentReps, isWarmUp: isWarmUp, isBodyweight: bodyweight)
            context.insert(set)
        }
        if !warmUp, !bodyweight, let estimate = WorkoutEngine.estimatedOneRepMax(weightLB: weight, reps: currentReps) {
            isNewBest = estimate > previousBest
        } else { isNewBest = false }
        activeSession.restUntil = warmUp ? nil : .now.addingTimeInterval(TimeInterval(lift.restSeconds))
        saveAndReload(context)
        if let refreshedLift = activeLifts.first(where: { $0.id == lift.id }) {
            selectedLiftID = refreshedLift.id
            currentWeight = weight
            currentReps = currentSets.count < refreshedLift.targetSets ? refreshedLift.targetReps : currentReps
        }
    }

    func skipRest() {
        activeSession?.restUntil = nil
        persist()
    }

    func addRestSeconds(_ seconds: Int) {
        guard let activeSession else { return }
        let baseline = max(activeSession.restUntil ?? .now, .now)
        activeSession.restUntil = baseline.addingTimeInterval(TimeInterval(max(seconds, 0)))
        persist()
    }

    func changeRestLength(_ seconds: Int) {
        guard let lift = currentLift else { return }
        lift.restSeconds = min(max(seconds, 15), 600)
        persist()
    }

    func setWarmUp(_ set: KoiWorkoutSet, value: Bool) {
        set.isWarmUp = value
        persist()
    }

    func deleteSet(_ set: KoiWorkoutSet) {
        guard let context else { return }
        context.delete(set)
        persist()
    }

    func endSession() -> WorkoutCompletionSummary? {
        guard let context, let session = activeSession else { return nil }
        let finish = Date.now
        session.endedAt = finish
        session.isComplete = true
        session.restUntil = nil
        if let record = movementDays.first(where: { calendar.isDate($0.date, inSameDayAs: session.startedAt) }) {
            record.didManuallyTrain = true
        } else {
            let day = KoiMovementDay(date: calendar.startOfDay(for: session.startedAt), didManuallyTrain: true)
            context.insert(day)
        }
        let sets = workoutSets.filter { $0.sessionID == session.id }
        let workSets = sets.filter { !$0.isWarmUp }
        let bests = activeLifts.compactMap { lift -> String? in
            guard !WorkoutNameRules.isBodyweight(lift.name) else { return nil }
            let liftSets = workSets.filter { $0.liftID == lift.id }
            guard let best = liftSets.compactMap({ WorkoutEngine.estimatedOneRepMax(weightLB: $0.weightLB, reps: $0.reps) }).max(), best >= bestOneRepMax(for: lift.name, excluding: session.id) else { return nil }
            return lift.name
        }
        let minutes = max(Int(finish.timeIntervalSince(session.startedAt) / 60), 0)
        let summary = WorkoutCompletionSummary(id: session.id, name: session.name, minutes: minutes, sets: workSets.count, volumeLB: Int(workSets.reduce(0) { $0 + $1.weightLB * Double($1.reps) }.rounded()), bestLifts: bests)
        completionSummary = summary
        persist()
        return summary
    }

    func clearCompletionSummary() { completionSummary = nil }
    func clearError() { errorMessage = nil }

    private func beginSession(name: String, group: String, routineID: UUID?, lifts: [(String, String, Int, Int, Int)]) {
        guard let context else { return }
        guard activeSession == nil else { return }
        let session = KoiWorkoutSession(name: name, muscleGroup: group, routineID: routineID)
        context.insert(session)
        for (index, value) in lifts.enumerated() {
            context.insert(KoiWorkoutLift(sessionID: session.id, name: value.0, muscleGroup: value.1, order: index, targetSets: value.2, targetReps: value.3, restSeconds: value.4))
        }
        do {
            try context.save()
            completionSummary = nil
            load(context)
            selectedLiftID = activeLifts.first?.id
            if let lift = currentLift { hydrateSet(for: lift) }
        } catch {
            logger.error("Unable to start workout.")
            errorMessage = "Couldn't start that workout. Try again."
        }
    }

    private func hydrateSet(for lift: KoiWorkoutLift) {
        if let session = activeSession,
           let current = workoutSets.filter({ $0.sessionID == session.id && $0.liftID == lift.id }).sorted(by: { $0.loggedAt < $1.loggedAt }).last {
            currentWeight = current.isBodyweight ? 0 : current.weightLB
            currentReps = current.reps
            lastContext = progressionCaption(for: lift)
            return
        }
        guard let progression = progression(for: lift) else {
            currentWeight = WorkoutNameRules.isBodyweight(lift.name) ? 0 : 45
            currentReps = lift.targetReps
            lastContext = ""
            return
        }
        currentWeight = progression.weightLB
        currentReps = progression.reps
        lastContext = progressionCaption(for: lift)
    }

    private func progression(for lift: KoiWorkoutLift) -> WorkoutProgression? {
        guard let previousLift = previousLift(for: lift) else { return nil }
        guard let previous = completedWorkouts.first(where: { $0.id == previousLift.sessionID }) else { return nil }
        let sets = workoutSets.filter { $0.sessionID == previous.id && $0.liftID == previousLift.id }.sorted { $0.loggedAt < $1.loggedAt }
        let inputs = sets.filter { !$0.isWarmUp }.map { WorkoutSetResult(weightLB: $0.weightLB, reps: $0.reps, estimatedOneRepMax: WorkoutEngine.estimatedOneRepMax(weightLB: $0.weightLB, reps: $0.reps, isBodyweight: $0.isBodyweight)) }
        return WorkoutEngine.nextStep(lastSets: inputs, targetReps: lift.targetReps, targetSets: lift.targetSets, isBodyweight: WorkoutNameRules.isBodyweight(lift.name))
    }

    private func progressionCaption(for lift: KoiWorkoutLift) -> String {
        guard let previousLift = previousLift(for: lift),
              let previous = completedWorkouts.first(where: { $0.id == previousLift.sessionID }) else { return "" }
        let sets = workoutSets.filter { $0.sessionID == previous.id && $0.liftID == previousLift.id && !$0.isWarmUp }.sorted { $0.loggedAt < $1.loggedAt }
        guard !sets.isEmpty else { return "" }
        let reps = sets.suffix(3).map { String($0.reps) }.joined(separator: ", ")
        let suggestion = progression(for: lift)
        let target = suggestion.map { " · Try \(formatWeight($0.weightLB)) × \($0.reps)" } ?? ""
        return "Last \(formatWeight(sets.last?.weightLB ?? 0)) × \(reps)\(target)"
    }

    private func bestOneRepMax(for liftName: String, excluding sessionID: UUID? = nil) -> Double {
        let liftIDs = Set(workoutLifts.filter { $0.name.localizedCaseInsensitiveCompare(liftName) == .orderedSame && $0.sessionID != sessionID }.map(\.id))
        return workoutSets.filter { liftIDs.contains($0.liftID) && !$0.isWarmUp && !$0.isBodyweight }
            .compactMap { WorkoutEngine.estimatedOneRepMax(weightLB: $0.weightLB, reps: $0.reps) }.max() ?? 0
    }

    private func previousLift(for lift: KoiWorkoutLift) -> KoiWorkoutLift? {
        let before = activeSession?.startedAt ?? .now
        return workoutLifts
            .filter { candidate in candidate.sessionID != activeSession?.id && candidate.name.localizedCaseInsensitiveCompare(lift.name) == .orderedSame && completedWorkouts.contains(where: { $0.id == candidate.sessionID && $0.startedAt < before }) }
            .sorted { lhs, rhs in
                let leftDate = completedWorkouts.first(where: { $0.id == lhs.sessionID })?.startedAt ?? .distantPast
                let rightDate = completedWorkouts.first(where: { $0.id == rhs.sessionID })?.startedAt ?? .distantPast
                return leftDate > rightDate
            }
            .first
    }

    private func loggedSetCount(for lift: KoiWorkoutLift) -> Int {
        guard let activeSession else { return 0 }
        return workoutSets.filter { $0.sessionID == activeSession.id && $0.liftID == lift.id && !$0.isWarmUp }.count
    }

    private var consecutiveTrainingDays: Int {
        var count = 0
        var cursor = calendar.startOfDay(for: .now)
        let trainedToday = sessions.contains { $0.isComplete && calendar.isDate($0.startedAt, inSameDayAs: cursor) }
            || movementDays.contains { $0.isTrainingDay && calendar.isDate($0.date, inSameDayAs: cursor) }
        if !trainedToday, let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = yesterday }
        for _ in 0..<14 {
            let trained = sessions.contains { $0.isComplete && calendar.isDate($0.startedAt, inSameDayAs: cursor) }
                || movementDays.contains { $0.isTrainingDay && calendar.isDate($0.date, inSameDayAs: cursor) }
            guard trained else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func persist() {
        guard let context else { return }
        do { try context.save(); load(context) }
        catch {
            logger.error("Unable to save workout data.")
            errorMessage = "Couldn't save that workout change. Try again."
        }
    }

    private func saveAndReload(_ context: ModelContext) {
        do { try context.save(); load(context) }
        catch {
            logger.error("Unable to save a workout set.")
            errorMessage = "Couldn't save that set. Try again."
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value.rounded(.towardZero) == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
