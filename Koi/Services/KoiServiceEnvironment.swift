import SwiftUI

private struct FoodEstimatingKey: EnvironmentKey {
    static let defaultValue: any FoodEstimating = EstimateClient()
}

extension EnvironmentValues {
    var foodEstimator: any FoodEstimating {
        get { self[FoodEstimatingKey.self] }
        set { self[FoodEstimatingKey.self] = newValue }
    }
}
