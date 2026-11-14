import Foundation
import HealthKit
import OSLog

struct HealthMovementSample: Equatable, Sendable {
    let date: Date
    let steps: Int
    let workoutCount: Int
}

struct HealthRecoverySnapshot: Equatable, Sendable {
    let reading: ReadinessReading
    let sleepHours: Double?
    let hrv: Double?
    let restingHeartRate: Double?
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

extension Notification.Name {
    static let koiHealthMovementDidChange = Notification.Name("KoiHealthMovementDidChange")
}

@MainActor
protocol HealthProviding: Sendable {
    var isAvailable: Bool { get }
    func requestReadAccess() async throws
    func movementData(from start: Date, to end: Date, calendar: Calendar) async throws -> [HealthMovementSample]
    func recoveryData(for date: Date, calendar: Calendar) async throws -> HealthRecoverySnapshot?
    func observeMovementChanges(_ onChange: @escaping @Sendable () -> Void)
}

extension HealthProviding {
    func recoveryData(for date: Date, calendar: Calendar) async throws -> HealthRecoverySnapshot? { nil }
    func observeMovementChanges(_ onChange: @escaping @Sendable () -> Void) {}
}

@MainActor
final class HealthService: HealthProviding {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Health")
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestReadAccess() async throws {
        guard isAvailable else { throw HealthServiceError.unavailable }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { throw HealthServiceError.unavailable }
        let recoveryTypes: [HKObjectType] = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        ].compactMap { $0 }
        let types: Set<HKObjectType> = Set([stepType, HKObjectType.workoutType()] + recoveryTypes)
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

    func observeMovementChanges(_ onChange: @escaping @Sendable () -> Void) {
        guard isAvailable,
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        for sampleType in [stepType, HKObjectType.workoutType()] as [HKSampleType] {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                defer { completion() }
                guard error == nil else { return }
                onChange()
            }
            observerQueries.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { success, error in
                if !success || error != nil { self.logger.error("Health background refresh was unavailable.") }
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

    func recoveryData(for date: Date, calendar: Calendar) async throws -> HealthRecoverySnapshot? {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let restingType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let dayStart = calendar.dateInterval(of: .day, for: date)?.start,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart),
              let baselineStart = calendar.date(byAdding: .day, value: -30, to: dayStart) else { return nil }
        let sleepSamples = try await samples(type: sleepType, from: baselineStart, to: dayStart)
        let hrvSamples = try await samples(type: hrvType, from: baselineStart, to: dayStart) as? [HKQuantitySample] ?? []
        let restingSamples = try await samples(type: restingType, from: baselineStart, to: dayStart) as? [HKQuantitySample] ?? []

        let validSleep = sleepSamples.compactMap { sample -> HKCategorySample? in
            guard let value = sample as? HKCategorySample,
                  value.value != HKCategoryValueSleepAnalysis.inBed.rawValue,
                  value.value != HKCategoryValueSleepAnalysis.awake.rawValue else { return nil }
            return value
        }
        let currentSleepSource = preferredSource(validSleep.filter { $0.endDate > previousDay && $0.endDate <= dayStart })
        let sleepSource = currentSleepSource ?? preferredSource(validSleep)
        let sourceSleep = validSleep.filter { $0.sourceRevision.source.bundleIdentifier == sleepSource?.source.bundleIdentifier }
        let lastNight = sourceSleep.filter { $0.endDate > previousDay && $0.endDate <= dayStart }
        let sleepHours = totalSleepHours(lastNight)
        let baselineByNight = Dictionary(grouping: sourceSleep.filter { $0.endDate <= previousDay }, by: { calendar.startOfDay(for: $0.endDate) })
        let sleepBaseline = average(baselineByNight.values.map(totalSleepHours))

        let hrvCurrent = preferredRecentSample(hrvSamples.filter { $0.endDate > previousDay && $0.endDate <= dayStart })
        let hrvSourceID = hrvCurrent?.sourceRevision.source.bundleIdentifier ?? preferredSource(hrvSamples)?.source.bundleIdentifier
        let sourceHRV = hrvSamples.filter { $0.sourceRevision.source.bundleIdentifier == hrvSourceID }
        let hrvBaseline = average(sourceHRV.filter { $0.endDate <= previousDay }.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) })
        let hrvValue = hrvCurrent?.quantity.doubleValue(for: .secondUnit(with: .milli))

        let restingCurrent = preferredRecentSample(restingSamples.filter { $0.endDate > previousDay && $0.endDate <= dayStart })
        let restingSourceID = restingCurrent?.sourceRevision.source.bundleIdentifier ?? preferredSource(restingSamples)?.source.bundleIdentifier
        let sourceResting = restingSamples.filter { $0.sourceRevision.source.bundleIdentifier == restingSourceID }
        let restingBaseline = average(sourceResting.filter { $0.endDate <= previousDay }.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) })
        let restingValue = restingCurrent?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

        let reading = ReadinessEngine.evaluate(ReadinessInput(sleepHours: sleepHours, sleepBaselineHours: sleepBaseline, hrv: hrvValue, hrvBaseline: hrvBaseline, restingHeartRate: restingValue, restingHeartRateBaseline: restingBaseline))
        guard let reading else { return nil }
        return HealthRecoverySnapshot(reading: reading, sleepHours: sleepHours, hrv: hrvValue, restingHeartRate: restingValue)
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

    private func samples(type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    private func preferredSource(_ samples: [HKSample]) -> HKSourceRevision? {
        samples.map(\.sourceRevision).sorted { sourceRank($0) < sourceRank($1) }.first
    }

    private func preferredRecentSample(_ samples: [HKQuantitySample]) -> HKQuantitySample? {
        samples.sorted {
            let rank = sourceRank($0.sourceRevision) - sourceRank($1.sourceRevision)
            return rank == 0 ? $0.endDate > $1.endDate : rank < 0
        }.first
    }

    private func sourceRank(_ source: HKSourceRevision) -> Int {
        (source.productType?.localizedCaseInsensitiveContains("watch") == true) || source.source.bundleIdentifier.localizedCaseInsensitiveContains("watch") ? 0 : 1
    }

    private func totalSleepHours(_ samples: [HKSample]) -> Double {
        samples.reduce(0) { $0 + max($1.endDate.timeIntervalSince($1.startDate), 0) } / 3_600
    }

    private func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }
}
