import SwiftUI

private struct FoodEstimatingKey: EnvironmentKey {
    static let defaultValue: any FoodEstimating = EstimateClient()
}

private struct HealthProvidingKey: EnvironmentKey {
    static let defaultValue: any HealthProviding = HealthService()
}

extension EnvironmentValues {
    var foodEstimator: any FoodEstimating {
        get { self[FoodEstimatingKey.self] }
        set { self[FoodEstimatingKey.self] = newValue }
    }

    var healthProvider: any HealthProviding {
        get { self[HealthProvidingKey.self] }
        set { self[HealthProvidingKey.self] = newValue }
    }
}
