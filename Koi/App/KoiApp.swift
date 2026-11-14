import SwiftUI
import SwiftData
import KoiShared

@main
struct KoiApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try KoiSchema.makeContainer()
        } catch {
            fatalError("Koi could not open its local data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            KoiRootView()
        }
        .modelContainer(modelContainer)
    }
}
