import XCTest
@testable import QuXCore

final class ParcelTests: XCTestCase {
    func testGroupsPickupAndOmitsFullTrackingNumberFromShare() throws {
        let result = try CainiaoParcelPage([
            "current": "1", "total": "1",
            "rows": [
                ["mailNo": "FAKE5123456789", "logisticsStatus": "AGENT_SIGN", "station": "测试驿站",
                 "pickupCode": "3-1-23", "partnerName": "测试快递"],
                ["mailNo": "FAKE0123456789", "logisticsStatus": "SIGN", "pickupCode": "expired"],
                ["mailNo": "FAKE6123456789", "logisticsStatus": "TRANSPORT"]
            ]
        ], expectedPage: 1)
        XCTAssertTrue(result.isLast)
        XCTAssertEqual(result.parcels.map(\.group), [.pickup, .signed, .transit])
        XCTAssertEqual(result.parcels[1].pickupCode, "")
        XCTAssertTrue(result.parcels[0].matches("3-1-23"))
        let sections = PickupSection.grouped(result.parcels.filter { !$0.pickupCode.isEmpty })
        XCTAssertEqual(PickupSection.shareText(sections), "测试驿站\n3-1-23  测试快递  尾号 6789")
    }

    func testPaginationRejectsUnexpectedOrIncompletePages() {
        XCTAssertThrowsError(try CainiaoParcelPage(["current": "1", "total": "2", "rows": []], expectedPage: 1))
        XCTAssertThrowsError(try CainiaoParcelPage(["current": "1", "total": "2", "rows": []], expectedPage: 2))
        XCTAssertThrowsError(try CainiaoParcelPage(["current": "1", "total": "201", "rows": []], expectedPage: 1))
        XCTAssertThrowsError(try CainiaoParcelPage(["current": "1", "total": "1"], expectedPage: 1))
    }

    func testEmptySnapshotRequiresExplicitCompletePage() throws {
        let result = try CainiaoParcelPage(["current": "1", "total": "0", "rows": []], expectedPage: 1)
        XCTAssertTrue(result.isLast)
        XCTAssertTrue(result.parcels.isEmpty)
    }

    func testRefusesInvalidRecordAndLoginError() {
        XCTAssertThrowsError(try CainiaoParcelPage([
            "current": "1", "total": "1", "rows": [["logisticsStatus": "AGENT_SIGN"]]
        ], expectedPage: 1))
        XCTAssertThrowsError(try CainiaoParcelPage(["error": "login"], expectedPage: 1)) {
            XCTAssertEqual(($0 as? CainiaoSyncError)?.errorDescription,
                           CainiaoSyncError.login.errorDescription)
        }
    }
}
