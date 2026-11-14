import SwiftUI
import UserNotifications
import TelemetryDeck

protocol AnalyticsProviding: Sendable {
    func signal(_ name: String)
    func signal(_ name: String, parameters: [String: String])
}

struct TelemetryAnalytics: AnalyticsProviding {
    func signal(_ name: String) {
        signal(name, parameters: [:])
    }

    func signal(_ name: String, parameters: [String: String] = [:]) {
        #if !DEBUG
        TelemetryDeck.signal(name, parameters: parameters)
        #endif
    }
}

private struct AnalyticsProvidingKey: EnvironmentKey {
    static let defaultValue: any AnalyticsProviding = TelemetryAnalytics()
}

private struct FoodEstimatingKey: EnvironmentKey {
    static let defaultValue: any FoodEstimating = EstimateClient()
}

private struct WorkoutImportingKey: EnvironmentKey {
    static let defaultValue: any WorkoutImporting = EstimateClient()
}

private struct HealthProvidingKey: EnvironmentKey {
    static let defaultValue: any HealthProviding = HealthService()
}

private struct RunTrackingKey: EnvironmentKey {
    static let defaultValue: (any RunTrackingProviding)? = nil
}

private struct NotificationProvidingKey: EnvironmentKey {
    static let defaultValue: (any NotificationProviding)? = nil
}

private struct CalendarProvidingKey: EnvironmentKey {
    static let defaultValue: (any CalendarProviding)? = nil
}

private struct BackupProvidingKey: EnvironmentKey {
    static let defaultValue: (any BackupProviding)? = nil
}

extension EnvironmentValues {
    var analyticsProvider: any AnalyticsProviding {
        get { self[AnalyticsProvidingKey.self] }
        set { self[AnalyticsProvidingKey.self] = newValue }
    }

    var foodEstimator: any FoodEstimating {
        get { self[FoodEstimatingKey.self] }
        set { self[FoodEstimatingKey.self] = newValue }
    }

    var workoutImporter: any WorkoutImporting {
        get { self[WorkoutImportingKey.self] }
        set { self[WorkoutImportingKey.self] = newValue }
    }

    var healthProvider: any HealthProviding {
        get { self[HealthProvidingKey.self] }
        set { self[HealthProvidingKey.self] = newValue }
    }

    var runTracker: (any RunTrackingProviding)? {
        get { self[RunTrackingKey.self] }
        set { self[RunTrackingKey.self] = newValue }
    }

    @MainActor var notificationProvider: any NotificationProviding {
        get { self[NotificationProvidingKey.self] ?? NotificationService() }
        set { self[NotificationProvidingKey.self] = newValue }
    }

    @MainActor var calendarProvider: any CalendarProviding {
        get { self[CalendarProvidingKey.self] ?? CalendarService() }
        set { self[CalendarProvidingKey.self] = newValue }
    }

    @MainActor var backupProvider: any BackupProviding {
        get { self[BackupProvidingKey.self] ?? BackupService() }
        set { self[BackupProvidingKey.self] = newValue }
    }
}
