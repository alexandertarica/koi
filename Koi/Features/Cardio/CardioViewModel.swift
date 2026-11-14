import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftData
import KoiShared

struct CardioWeeklyStats: Equatable {
    let sessions: Int
    let minutes: Int
    let miles: Double
}

struct CardioWeekMileage: Identifiable, Equatable {
    let start: Date
    let miles: Double
    var id: Date { start }
    var label: String { start.formatted(.dateTime.month(.abbreviated).day()) }
}

@MainActor
@Observable
final class CardioViewModel {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Cardio")
    private let calendar: Calendar
    private var context: ModelContext?
    private var tracker: (any RunTrackingProviding)?
    private var sessions: [KoiCardioSession] = []
    private var movementDays: [KoiMovementDay] = []
    private var saveTask: Task<Void, Never>?

    private(set) var activeSession: KoiCardioSession?
    private(set) var selectedSession: KoiCardioSession?
    private(set) var errorMessage: String?

    init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    var isTrackingRun: Bool { tracker?.isTracking ?? false }
    var liveDistanceMeters: Double { tracker?.distanceMeters ?? activeSession?.distanceMeters ?? 0 }
    var livePaceSecondsPerMile: Double? { tracker?.currentPaceSecondsPerMile }
    var liveRoute: [RunLocationPoint] { tracker?.route ?? [] }
    var elapsedSeconds: Int {
        guard let activeSession else { return 0 }
        return max(Int(Date.now.timeIntervalSince(activeSession.startedAt)), activeSession.durationSeconds)
    }

    var completedSessions: [KoiCardioSession] { sessions.filter(\.isComplete).sorted { $0.startedAt > $1.startedAt } }
    var recentSessions: [KoiCardioSession] { Array(completedSessions.prefix(10)) }
    var weeklyStats: CardioWeeklyStats {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .distantPast
        let week = completedSessions.filter { $0.startedAt >= start }
        let miles = week.reduce(0) { $0 + ($1.distanceMeters / 1_609.344) }
        return CardioWeeklyStats(sessions: week.count, minutes: week.reduce(0) { $0 + $1.durationSeconds } / 60, miles: miles)
    }

    var eightWeekMileage: [CardioWeekMileage] {
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: startOfThisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let miles = completedSessions.filter { $0.startedAt >= start && $0.startedAt < end }.reduce(0) { $0 + $1.distanceMeters / 1_609.344 }
            return CardioWeekMileage(start: start, miles: miles)
        }
    }

    var longestDistanceMiles: Double { completedSessions.map { $0.distanceMeters / 1_609.344 }.max() ?? 0 }
    var fastestPace: Double? {
        completedSessions.filter { $0.activity == "Outdoor run" || $0.activity == "Treadmill" }
            .compactMap(\.paceSecondsPerMile).filter { $0 > 0 }.min()
    }
    var bestFiveKSeconds: Int? {
        completedSessions.compactMap { session -> Int? in
            guard session.activity == "Outdoor run" || session.activity == "Treadmill" else { return nil }
            let miles = session.distanceMeters / 1_609.344
            guard miles >= 3.1069 else { return nil }
            return Int((Double(session.durationSeconds) * 3.1069 / miles).rounded())
        }.min()
    }
    var usualActivities: [String] {
        let counts = Dictionary(grouping: completedSessions, by: { $0.activity == "Class" ? $0.detail : $0.activity })
        return counts.sorted { lhs, rhs in lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count > rhs.value.count }.prefix(4).map(\.key)
    }
    var activityCounts: [(name: String, count: Int)] {
        Dictionary(grouping: completedSessions, by: { $0.activity == "Class" ? $0.detail : $0.activity })
            .map { (name: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }

    func load(_ context: ModelContext, tracker: any RunTrackingProviding) {
        self.context = context
        self.tracker = tracker
        do {
            sessions = try context.fetch(FetchDescriptor<KoiCardioSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            movementDays = try context.fetch(FetchDescriptor<KoiMovementDay>())
            activeSession = sessions.first(where: { !$0.isComplete })
            if activeSession?.activity == "Outdoor run" {
                if tracker.isTracking { beginRouteSaving() }
                else { tracker.reset() }
            }
        } catch {
            logger.error("Unable to load cardio sessions.")
            errorMessage = "Couldn't load your activities. Try again."
        }
    }

    func startOutdoorRun() async {
        guard let context, let tracker, activeSession == nil else { return }
        let session = KoiCardioSession(activity: "Outdoor run")
        context.insert(session)
        do {
            try context.save()
            sessions.insert(session, at: 0)
            activeSession = session
            try await tracker.start(resuming: [])
            beginRouteSaving()
        } catch {
            context.delete(session)
            sessions.removeAll { $0.id == session.id }
            activeSession = nil
            do { try context.save() }
            catch { logger.error("Unable to discard a failed run start.") }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't start this run. Try again."
        }
    }

    func resumeOutdoorRun() async {
        guard let session = activeSession, session.activity == "Outdoor run", let tracker else { return }
        do {
            let route = decodeRoute(session.routeData)
            try await tracker.start(resuming: route)
            beginRouteSaving()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't resume this run. Try again."
        }
    }

    func startTreadmill() { beginTimedSession(activity: "Treadmill") }

    func logManualActivity(activity: String, detail: String = "", minutes: Int, miles: Double = 0) {
        guard let context, activeSession == nil else { return }
        let session = KoiCardioSession(activity: activity, detail: detail, startedAt: .now, durationSeconds: max(minutes, 0) * 60, distanceMeters: max(miles.isFinite ? miles : 0, 0) * 1_609.344)
        session.endedAt = .now
        session.isComplete = true
        context.insert(session)
        markTrainingDay(session.startedAt, context: context)
        saveAndReload(context)
    }

    func setTreadmillDistance(miles: Double) {
        guard let session = activeSession, session.activity == "Treadmill" else { return }
        session.distanceMeters = max(miles.isFinite ? miles : 0, 0) * 1_609.344
        saveSilently()
    }

    func finishActiveSession() {
        guard let context, let session = activeSession else { return }
        saveTask?.cancel()
        saveTask = nil
        if session.activity == "Outdoor run", let tracker {
            tracker.stop()
            updateRunRecord(session)
        }
        let finishedAt = Date.now
        session.durationSeconds = max(Int(finishedAt.timeIntervalSince(session.startedAt)), session.durationSeconds)
        session.endedAt = finishedAt
        session.isComplete = true
        markTrainingDay(session.startedAt, context: context)
        saveAndReload(context)
        tracker?.reset()
    }

    func discardActiveSession() {
        guard let context, let session = activeSession else { return }
        saveTask?.cancel()
        tracker?.reset()
        context.delete(session)
        saveAndReload(context)
    }

    func select(_ session: KoiCardioSession) { selectedSession = session }
    func clearSelection() { selectedSession = nil }
    func clearError() { errorMessage = nil }

    func repeatActivity(_ name: String) {
        if name == "Outdoor run" {
            Task { await startOutdoorRun() }
            return
        }
        if let session = completedSessions.first(where: { $0.activity == name || $0.detail == name }) {
            logManualActivity(activity: session.activity, detail: session.detail, minutes: session.durationSeconds / 60, miles: session.distanceMeters / 1_609.344)
        }
    }

    func route(for session: KoiCardioSession) -> [RunLocationPoint] { decodeRoute(session.routeData) }
    func mileSplits(for session: KoiCardioSession) -> [Int] { decodeSplits(session.mileSplitsData) }

    private func beginTimedSession(activity: String) {
        guard let context, activeSession == nil else { return }
        let session = KoiCardioSession(activity: activity)
        context.insert(session)
        do { try context.save(); sessions.insert(session, at: 0); activeSession = session }
        catch { logger.error("Unable to start a cardio session."); errorMessage = "Couldn't start that session. Try again." }
    }

    private func beginRouteSaving() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let activeSession = self.activeSession, self.isTrackingRun else { break }
                self.updateRunRecord(activeSession)
                self.saveSilently()
            }
        }
    }

    private func updateRunRecord(_ session: KoiCardioSession) {
        guard let tracker else { return }
        session.distanceMeters = tracker.distanceMeters
        session.durationSeconds = max(Int(Date.now.timeIntervalSince(session.startedAt)), 0)
        session.routeData = try? JSONEncoder().encode(tracker.route)
        session.mileSplitsData = try? JSONEncoder().encode(computeMileSplits(tracker.route, start: session.startedAt))
    }

    private func computeMileSplits(_ route: [RunLocationPoint], start: Date) -> [Int] {
        guard route.count > 1 else { return [] }
        var distance = 0.0
        var splits: [Int] = []
        var nextMile = 1_609.344
        for pair in zip(route, route.dropFirst()) {
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            distance += a.distance(from: b)
            while distance >= nextMile {
                splits.append(max(Int(pair.1.timestamp.timeIntervalSince(start)), 0))
                nextMile += 1_609.344
            }
        }
        return splits
    }

    private func markTrainingDay(_ date: Date, context: ModelContext) {
        if let day = movementDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            day.didManuallyTrain = true
        } else {
            let day = KoiMovementDay(date: calendar.startOfDay(for: date), didManuallyTrain: true)
            context.insert(day)
            movementDays.append(day)
        }
    }

    private func saveSilently() {
        guard let context else { return }
        do { try context.save() }
        catch { logger.error("Unable to save live cardio data.") }
    }

    private func saveAndReload(_ context: ModelContext) {
        do {
            try context.save()
            sessions = try context.fetch(FetchDescriptor<KoiCardioSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            activeSession = sessions.first(where: { !$0.isComplete })
        } catch {
            logger.error("Unable to save a cardio session.")
            errorMessage = "Couldn't save that activity. Try again."
        }
    }

    private func decodeRoute(_ data: Data?) -> [RunLocationPoint] { data.flatMap { try? JSONDecoder().decode([RunLocationPoint].self, from: $0) } ?? [] }
    private func decodeSplits(_ data: Data?) -> [Int] { data.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? [] }
}
