import Foundation
import HealthKit
import OSLog

struct HealthMovementSample: Equatable, Sendable {
    let date: Date
    let steps: Int
    let workoutCount: Int
}

enum HealthServiceError: LocalizedError {
    case unavailable
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn't available on this device."
        case .queryFailed: "Couldn't read movement from Apple Health. Try again."
        }
    }
}

@MainActor
protocol HealthProviding: Sendable {
    var isAvailable: Bool { get }
    func requestReadAccess() async throws
    func movementData(from start: Date, to end: Date, calendar: Calendar) async throws -> [HealthMovementSample]
}

@MainActor
final class HealthService: HealthProviding {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Health")
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAccess() async throws {
        guard isAvailable else { throw HealthServiceError.unavailable }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { throw HealthServiceError.unavailable }
        let types: Set<HKObjectType> = [stepType, HKObjectType.workoutType()]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: types) { success, error in
                if let error {
                    self.logger.error("Health authorization request failed.")
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthServiceError.queryFailed)
                }
            }
        }
    }

    func movementData(from start: Date, to end: Date, calendar: Calendar) async throws -> [HealthMovementSample] {
        guard isAvailable else { throw HealthServiceError.unavailable }
        let workouts = try await workouts(from: start, to: end)
        let workoutCounts = Dictionary(grouping: workouts, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        var result: [HealthMovementSample] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let count = try await stepCount(from: cursor, to: min(next, end))
            result.append(HealthMovementSample(date: cursor, steps: count, workoutCount: workoutCounts[cursor] ?? 0))
            cursor = next
        }
        return result
    }

    private func stepCount(from start: Date, to end: Date) async throws -> Int {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { throw HealthServiceError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: steps.isFinite ? max(Int(steps.rounded()), 0) : 0)
            }
            store.execute(query)
        }
    }

    private func workouts(from start: Date, to end: Date) async throws -> [Date] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Date], Error>) in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let dates = (samples as? [HKWorkout] ?? []).map(\.startDate)
                continuation.resume(returning: dates)
            }
            store.execute(query)
        }
    }
}
