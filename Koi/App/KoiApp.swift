import SwiftUI
import SwiftData
import KoiShared

@main
struct KoiApp: App {
    private let modelContainer: ModelContainer
    private let runTracker: RunTracker

    init() {
        runTracker = RunTracker()
        do {
            modelContainer = try KoiSchema.makeContainer()
        } catch {
            fatalError("Koi could not open its local data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            KoiRootView().environment(\.runTracker, runTracker)
        }
        .modelContainer(modelContainer)
    }
}
