import XCTest
@testable import LuckinCore

final class RandomTests: XCTestCase {
    func candidates() -> [Candidate] { (0..<3).map { Candidate(id: String($0), productId: "test-\($0)", name: "测试\($0)", sku: "MOCK-\($0)", preferences: [], weight: Double($0 + 1)) } }
    func testEqualBoundariesIgnoreWeights() throws {
        let list = candidates()
        XCTAssertEqual(try RandomPicker.pick(list, weighted: false, previous: nil, avoid: false, unit: 0).id, "0")
        XCTAssertEqual(try RandomPicker.pick(list, weighted: false, previous: nil, avoid: false, unit: 0.34).id, "1")
        XCTAssertEqual(try RandomPicker.pick(list, weighted: false, previous: nil, avoid: false, unit: 0.99).id, "2")
    }
    func testWeightedBoundaries() throws {
        let list = candidates()
        XCTAssertEqual(try RandomPicker.pick(list, weighted: true, previous: nil, avoid: false, unit: 0.16).id, "0")
        XCTAssertEqual(try RandomPicker.pick(list, weighted: true, previous: nil, avoid: false, unit: 0.17).id, "1")
        XCTAssertEqual(try RandomPicker.pick(list, weighted: true, previous: nil, avoid: false, unit: 0.51).id, "2")
    }
    func testRepeatAndDisable() throws {
        var list = candidates(); list[2].enabled = false
        XCTAssertEqual(try RandomPicker.pick(list, weighted: false, previous: "0", avoid: true, unit: 0).id, "1")
        list[1].enabled = false
        XCTAssertEqual(try RandomPicker.pick(list, weighted: false, previous: "0", avoid: true, unit: 0).id, "0")
        list[0].enabled = false
        XCTAssertThrowsError(try RandomPicker.pick(list, weighted: false, previous: nil, avoid: false))
    }
    func testConfigurationRoundTripAndVersionRejection() throws {
        var c = Configuration.fresh(); c.pools[0].candidates = candidates()
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(c, decoded); try decoded.validate()
        c.schemaVersion = 2; XCTAssertThrowsError(try c.validate())
    }
    func testZeroAndNonFiniteWeightsRejected() throws {
        var c = Configuration.fresh(); c.pools[0].candidates = candidates(); c.pools[0].candidates[0].weight = 0
        XCTAssertThrowsError(try c.validate())
        var list = candidates(); list[0].weight = .infinity
        XCTAssertThrowsError(try RandomPicker.pick(list, weighted: true, previous: nil, avoid: false))
    }
    func testPickupNotShownForUnpaidStatus() {
        let o = CoffeeOrder(id: "test", state: "awaitingPayment", createdAt: "now", mode: "mock", poolId: "pool", pickupCode: "not-for-display")
        XCTAssertFalse(o.paid)
    }
}
