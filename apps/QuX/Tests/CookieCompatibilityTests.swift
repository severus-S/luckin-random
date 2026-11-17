import XCTest
@testable import QuXCore

final class CookieCompatibilityTests: XCTestCase {
    func cookie(_ name: String, domain: String = ".taobao.com", value: String = "synthetic") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE",
                                .expires: Date(timeIntervalSince1970: 4_000_000_000)])!
    }
    func testCoreCookiesCloneWithValueAndAttributes() throws {
        for name in ["cookie2", "unb", "_tb_token_", "sgcookie", "t", "_m_h5_tk", "_m_h5_tk_enc"] {
            let source = cookie(name)
            let clone = try XCTUnwrap(CookieCompatibility.cainiaoClone(source))
            XCTAssertEqual(clone.domain, ".cainiao.com")
            XCTAssertEqual(clone.name, source.name)
            XCTAssertEqual(clone.value, source.value)
            XCTAssertEqual(clone.path, source.path)
            XCTAssertEqual(clone.isSecure, source.isSecure)
            XCTAssertEqual(clone.expiresDate, source.expiresDate)
        }
    }
    func testRejectsUnrelatedAndLookalikeDomains() {
        for domain in ["eviltaobao.com", "taobao.com.evil.test", ".cainiao.com", ".tmall.com"] {
            XCTAssertNil(CookieCompatibility.cainiaoClone(cookie("cookie2", domain: domain)))
        }
        XCTAssertNotNil(CookieCompatibility.cainiaoClone(cookie("cookie2", domain: "login.m.taobao.com")))
    }
    func testFreshResponseWinsOverSnapshotAndWritesAreUnique() {
        let old = cookie("cookie2", value: "old")
        let fresh = cookie("cookie2", value: "fresh")
        let writes = CookieCompatibility.writes([old, cookie("cookie2", domain: ".cainiao.com", value: "old-cn"), fresh])
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(writes.allSatisfy { $0.value == "fresh" })
    }
}
