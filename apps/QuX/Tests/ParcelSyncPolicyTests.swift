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
    func testManualCheckRunsOnlyOnCainiaoBusinessPage() {
        XCTAssertTrue(ParcelSyncPolicy.isBusinessPage(URL(string: "https://page.cainiao.com/guoguo/app-myexpress-taobao/")!))
        for raw in ["https://login.m.taobao.com/login.htm", "https://cnlogin.cainiao.com/login", "https://page.cainiao.com/passport/auth", "https://cnlogin.cainiao.com/doSsoLogin"] {
            XCTAssertFalse(ParcelSyncPolicy.isBusinessPage(URL(string: raw)!))
        }
    }
    func testSameNameCookiesUseOneTargetDomainWinnerForHeaderAndSign() {
        func token(_ value: String, domain: String, path: String = "/") -> HTTPCookie {
            HTTPCookie(properties: [.name: "_m_h5_tk", .value: value, .domain: domain, .path: path])!
        }
        let endpoint = URL(string: "https://acs.m.cainiao.com/h5/test/1.0/")!
        let input = [token("taobao_123", domain: ".taobao.com"), token("root_123", domain: ".cainiao.com"), token("target_123", domain: "acs.m.cainiao.com"), token("private_123", domain: ".cainiao.com", path: "/private")]
        for values in [input, Array(input.reversed())] {
            let selected = ParcelSyncPolicy.cookies(values, for: endpoint)
            XCTAssertEqual(selected.count, 1)
            XCTAssertEqual(selected.first?.value, "target_123")
            XCTAssertEqual(ParcelSyncPolicy.cookieHeader(selected), "_m_h5_tk=target_123")
            XCTAssertEqual(CainiaoLogin.signingToken(selected.first?.value), "target")
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
