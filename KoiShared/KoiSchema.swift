import Foundation
import SwiftData

/// The shared model schema is used by the app and its widget extension.
public enum KoiSchema {
    public static let models: [any PersistentModel.Type] = [
        KoiDay.self,
        KoiHabit.self,
        KoiHabitLog.self,
        KoiTask.self,
        KoiFoodEntry.self,
        KoiNutrientGoal.self,
        KoiNutrientEntry.self,
        KoiSupplement.self,
        KoiSupplementLog.self,
        KoiMovementGoal.self,
        KoiMovementDay.self,
        KoiWorkoutRoutine.self,
        KoiRoutineLift.self,
        KoiWorkoutSession.self,
        KoiWorkoutLift.self,
        KoiWorkoutSet.self,
        KoiCardioSession.self
    ]

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(
            "Koi",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .identifier(KoiAppGroup.identifier),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

public enum KoiAppGroup {
    public static let identifier = "group.com.alexandertarica.koi"
    public static let widgetSnapshotKey = "widget.balance.snapshot"
}
