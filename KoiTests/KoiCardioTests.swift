import Observation
import XCTest
import SwiftData
import KoiShared
@testable import Koi

@MainActor
@Observable
private final class FakeRunTracker: RunTrackingProviding {
    private(set) var isTracking = false
    private(set) var route: [RunLocationPoint] = []
    private(set) var distanceMeters = 0.0
    private(set) var currentPaceSecondsPerMile: Double?

    func start(resuming route: [RunLocationPoint]) async throws {
        self.route = route
        isTracking = true
    }
    func stop() { isTracking = false }
    func reset() { isTracking = false; route = []; distanceMeters = 0; currentPaceSecondsPerMile = nil }
    func record(points: [RunLocationPoint], distanceMeters: Double, pace: Double?) {
        route = points
        self.distanceMeters = max(distanceMeters, 0)
        currentPaceSecondsPerMile = pace
    }
}

@MainActor
@Observable
private final class DeniedRunTracker: RunTrackingProviding {
    private(set) var isTracking = false
    private(set) var route: [RunLocationPoint] = []
    private(set) var distanceMeters = 0.0
    private(set) var currentPaceSecondsPerMile: Double?

    func start(resuming route: [RunLocationPoint]) async throws { throw RunTrackingError.permissionDenied }
    func stop() { isTracking = false }
    func reset() { isTracking = false; route = []; distanceMeters = 0; currentPaceSecondsPerMile = nil }
}

@MainActor
final class KoiCardioTests: XCTestCase {
    func testManualActivitiesPersistSummariesAndTrainingCredit() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = CardioViewModel()
        model.load(context, tracker: FakeRunTracker())

        model.logManualActivity(activity: "Class", detail: "Pilates", minutes: 45)
        model.logManualActivity(activity: "Hike", minutes: 60, miles: 5)
        model.logManualActivity(activity: "Outdoor run", minutes: 60, miles: 5)

        XCTAssertEqual(model.weeklyStats.sessions, 3)
        XCTAssertEqual(model.weeklyStats.minutes, 165)
        XCTAssertEqual(model.weeklyStats.miles, 10, accuracy: 0.01)
        XCTAssertEqual(model.longestDistanceMiles, 5, accuracy: 0.01)
        XCTAssertNotNil(model.bestFiveKSeconds)
        XCTAssertEqual(model.usualActivities.first, "Hike")
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiMovementDay>()).first).didManuallyTrain)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiCardioSession>()).count, 3)
    }

    func testOutdoorRunSavesRouteDistancePaceSplitsAndCanResume() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let tracker = FakeRunTracker()
        let model = CardioViewModel()
        model.load(context, tracker: tracker)

        await model.startOutdoorRun()
        XCTAssertTrue(model.isTrackingRun)
        let started = try XCTUnwrap(model.activeSession?.startedAt)
        tracker.record(points: [
            RunLocationPoint(latitude: 0, longitude: 0, timestamp: started.addingTimeInterval(1)),
            RunLocationPoint(latitude: 0.0147, longitude: 0, timestamp: started.addingTimeInterval(610))
        ], distanceMeters: 1_610, pace: 610)
        model.finishActiveSession()

        let run = try XCTUnwrap(model.completedSessions.first)
        XCTAssertEqual(run.activity, "Outdoor run")
        XCTAssertEqual(run.distanceMeters, 1_610, accuracy: 0.1)
        XCTAssertEqual(run.paceSecondsPerMile ?? 0, Double(run.durationSeconds) / (1_610 / 1_609.344), accuracy: 0.1)
        XCTAssertEqual(model.route(for: run).count, 2)
        XCTAssertEqual(model.mileSplits(for: run).count, 1)
        XCTAssertFalse(tracker.isTracking)
        XCTAssertTrue(try XCTUnwrap(context.fetch(FetchDescriptor<KoiMovementDay>()).first).didManuallyTrain)
    }

    func testTreadmillCompletesAndDeniedLocationLeavesNoPartialRun() async throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let model = CardioViewModel()
        model.load(context, tracker: FakeRunTracker())
        model.startTreadmill()
        model.setTreadmillDistance(miles: 2.25)
        model.finishActiveSession()
        XCTAssertEqual(model.weeklyStats.sessions, 1)
        XCTAssertEqual(model.weeklyStats.miles, 2.25, accuracy: 0.01)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiCardioSession>()).filter(\.isComplete).count, 1)

        let deniedModel = CardioViewModel()
        deniedModel.load(context, tracker: DeniedRunTracker())
        await deniedModel.startOutdoorRun()
        XCTAssertNil(deniedModel.activeSession)
        XCTAssertNotNil(deniedModel.errorMessage)
        XCTAssertEqual(try context.fetch(FetchDescriptor<KoiCardioSession>()).count, 1)
    }
}
