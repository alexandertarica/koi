import SwiftUI
import SwiftData
import KoiShared
import TelemetryDeck

@main
struct KoiApp: App {
    private let modelContainer: ModelContainer
    private let runTracker: RunTracker

    init() {
        runTracker = RunTracker()
        #if !DEBUG
        TelemetryDeck.initialize(config: .init(appID: "57EF3910-7D36-44AF-AA9B-E63F815F5ECA"))
        #endif
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
