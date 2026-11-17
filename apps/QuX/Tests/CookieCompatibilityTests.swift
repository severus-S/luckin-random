import XCTest
@testable import QuXCore

final class CookieCompatibilityTests: XCTestCase {
    func cookie(_ name: String, domain: String = ".taobao.com", value: String = "synthetic") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE",
                                .expires: Date(timeIntervalSince1970: 4_000_000_000)])!
    }
    func testCleanupRemovesOnlyLegacyCainiaoCopies() throws {
        for name in ["cookie2", "unb", "_tb_token_", "sgcookie", "t", "_m_h5_tk", "_m_h5_tk_enc"] {
            XCTAssertTrue(CookieCompatibility.shouldRemoveLegacyCopy(cookie(name, domain: ".cainiao.com")))
            XCTAssertFalse(CookieCompatibility.shouldRemoveLegacyCopy(cookie(name)))
            XCTAssertFalse(CookieCompatibility.shouldRemoveLegacyCopy(cookie(name, domain: "cnlogin.cainiao.com")))
        }
        XCTAssertFalse(CookieCompatibility.shouldRemoveLegacyCopy(cookie("cncc", domain: ".cainiao.com")))
    }
    func testSessionRequiresBothValidTaobaoCookies() {
        XCTAssertTrue(CookieCompatibility.hasTaobaoSession([cookie("cookie2"), cookie("unb")]))
        XCTAssertFalse(CookieCompatibility.hasTaobaoSession([cookie("cookie2")]))
        XCTAssertFalse(CookieCompatibility.hasTaobaoSession([cookie("cookie2"), cookie("unb", value: "")]))
        XCTAssertFalse(CookieCompatibility.hasTaobaoSession([cookie("cookie2", domain: "taobao.com.evil.test"), cookie("unb")]))
        XCTAssertFalse(CookieCompatibility.hasTaobaoSession([cookie("cookie2"), cookie("unb")], now: Date(timeIntervalSince1970: 5_000_000_000)))
    }
    func testHandoffMarkersAndCrossSiteTransition() {
        XCTAssertTrue(CookieCompatibility.isQuickEnterHandoff(URL(string: "https://login.m.taobao.com/mini_apply_st.htm")!, source: nil))
        XCTAssertTrue(CookieCompatibility.isQuickEnterHandoff(URL(string: "https://pass.tmall.hk/vst.htm")!, source: nil))
        XCTAssertTrue(CookieCompatibility.isQuickEnterHandoff(URL(string: "https://page.cainiao.com/path")!, source: URL(string: "https://login.m.taobao.com/login.htm")!))
        XCTAssertFalse(CookieCompatibility.isQuickEnterHandoff(URL(string: "https://evil.test/vst")!, source: nil))
    }
    func testLoopWindowExpires() {
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(CookieCompatibility.inLoopWindow(passedAt: start, now: start.addingTimeInterval(4.9)))
        XCTAssertFalse(CookieCompatibility.inLoopWindow(passedAt: start, now: start.addingTimeInterval(5.1)))
        XCTAssertFalse(CookieCompatibility.inLoopWindow(passedAt: nil, now: start))
        XCTAssertFalse(CookieCompatibility.inLoopWindow(passedAt: start, now: start.addingTimeInterval(-1)))
    }
}
