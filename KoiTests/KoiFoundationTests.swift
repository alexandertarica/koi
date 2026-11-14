import XCTest
import SwiftData
import KoiShared

final class KoiFoundationTests: XCTestCase {
    func testInMemoryContainerCanPersistCoreModels() throws {
        let container = try KoiSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let day = KoiDay(date: .now, balance: 0.72)
        context.insert(day)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KoiDay>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.balance, 0.72)
    }
}
