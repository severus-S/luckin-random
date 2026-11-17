import XCTest
@testable import QuXCore

final class ParcelSyncPolicyTests: XCTestCase {
    func cookie(_ name: String, domain: String = ".taobao.com", path: String = "/") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: "synthetic", .domain: domain, .path: path])!
    }
    func testReadinessAllowsTrustedCookieMarkersIncludingHttpOnly() {
        for name in ["cookie2", "unb", "_m_h5_tk", "cna"] {
            XCTAssertTrue(ParcelSyncPolicy.hasSyncCookie([cookie(name)]))
            XCTAssertTrue(ParcelSyncPolicy.hasSyncCookie([cookie(name, domain: ".cainiao.com")]))
            XCTAssertFalse(ParcelSyncPolicy.hasSyncCookie([cookie(name, domain: ".taobao.com.evil.test")]))
        }
    }
    func testNativeCookiesNeverMixDomainsOrPaths() {
        let url = URL(string: "https://acs.m.taobao.com/h5/test/1.0/")!
        let cookies = [cookie("taobao"), cookie("cainiao", domain: ".cainiao.com"), cookie("wrong-path", path: "/private"), cookie("host-only", domain: "login.taobao.com")]
        XCTAssertEqual(ParcelSyncPolicy.cookies(cookies, for: url).map(\.name), ["taobao"])
        XCTAssertTrue(ParcelSyncPolicy.allowedGateway(url))
        XCTAssertFalse(ParcelSyncPolicy.allowedGateway(URL(string: "https://acs.m.taobao.com.evil.test/h5/test/1.0/")!))
    }
    func testRepeatedMainLoginReturnsStayBlockedAndIframesAreAllowed() {
        for host in ["login.m.taobao.com", "login.taobao.com"] {
            let url = URL(string: "https://\(host)/login.htm")!
            for _ in 0..<10 {
                XCTAssertTrue(ParcelSyncPolicy.blocksLoginReturn(url, mainFrame: true, passedQuickEnter: true, manualLogin: false, cookies: []))
            }
            XCTAssertTrue(ParcelSyncPolicy.blocksLoginReturn(url, mainFrame: true, passedQuickEnter: false, manualLogin: false, cookies: [cookie("unb")]))
            XCTAssertFalse(ParcelSyncPolicy.blocksLoginReturn(url, mainFrame: false, passedQuickEnter: true, manualLogin: false, cookies: []))
            XCTAssertFalse(ParcelSyncPolicy.blocksLoginReturn(url, mainFrame: true, passedQuickEnter: true, manualLogin: true, cookies: []))
        }
    }
    func testEmptyAPIPageAndPickupMapping() throws {
        let empty = try ParcelSyncPolicy.page(["data": ["currentPage": 1, "totalPage": 0, "packages": []]], expectedPage: 1)
        XCTAssertTrue(empty.isLast)
        XCTAssertTrue(empty.parcels.isEmpty)
        let row: [String: Any] = ["mailNo": "synthetic1234", "logisticsStatus": "AGENT_SIGN", "packageStation": ["showAuthCode": true, "authCode": "1-2-3", "stationName": "合成驿站"]]
        let result = try ParcelSyncPolicy.page(["data": ["currentPage": "1", "totalPage": "1", "packages": [row]]], expectedPage: 1)
        XCTAssertEqual(result.parcels.first?.pickupCode, "1-2-3")
        XCTAssertThrowsError(try ParcelSyncPolicy.page(["data": ["currentPage": 1, "totalPage": 2, "packages": []]], expectedPage: 1))
    }
}
