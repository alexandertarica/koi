@preconcurrency import CoreLocation
import Foundation
import Observation

struct RunLocationPoint: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

enum RunTrackingError: LocalizedError {
    case unavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unavailable: "Location services aren't available on this device."
        case .permissionDenied: "Allow location access in Settings to record an outdoor run."
        }
    }
}

@MainActor
protocol RunTrackingProviding: AnyObject, Observable, Sendable {
    var isTracking: Bool { get }
    var route: [RunLocationPoint] { get }
    var distanceMeters: Double { get }
    var currentPaceSecondsPerMile: Double? { get }
    func start(resuming route: [RunLocationPoint]) async throws
    func stop()
    func reset()
}

@MainActor
@Observable
final class RunTracker: NSObject, RunTrackingProviding, @preconcurrency CLLocationManagerDelegate {
    private(set) var isTracking = false
    private(set) var route: [RunLocationPoint] = []
    private(set) var distanceMeters = 0.0
    private(set) var currentPaceSecondsPerMile: Double?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var previousLocation: CLLocation?
    @ObservationIgnored private var authorizationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start(resuming route: [RunLocationPoint] = []) async throws {
        guard CLLocationManager.locationServicesEnabled() else { throw RunTrackingError.unavailable }
        switch manager.authorizationStatus {
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            throw RunTrackingError.permissionDenied
        @unknown default:
            throw RunTrackingError.permissionDenied
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            throw RunTrackingError.permissionDenied
        }
        self.route = route
        distanceMeters = zip(route, route.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude).distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        previousLocation = route.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    func reset() {
        stop()
        route = []
        distanceMeters = 0
        currentPaceSecondsPerMile = nil
        previousLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation = nil
            continuation.resume()
        case .denied, .restricted:
            authorizationContinuation = nil
            continuation.resume(throwing: RunTrackingError.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            authorizationContinuation = nil
            continuation.resume(throwing: RunTrackingError.permissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 35 {
            if let previousLocation, location.timestamp > previousLocation.timestamp {
                let segment = location.distance(from: previousLocation)
                guard segment < 100 else {
                    self.previousLocation = location
                    continue
                }
                if segment > 0 { distanceMeters += segment }
                if location.speed >= 0.5 { currentPaceSecondsPerMile = 1_609.344 / location.speed }
            }
            if route.last?.timestamp != location.timestamp {
                route.append(RunLocationPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timestamp: location.timestamp))
            }
            previousLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { stop() }
    }
}
