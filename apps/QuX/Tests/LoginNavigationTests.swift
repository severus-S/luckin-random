import XCTest
@testable import QuXCore

final class LoginNavigationTests: XCTestCase {
    func testWidgetRedirectReturnsToTheRequestedIdentityPage() throws {
        let destination = URL(string: "https://page.cainiao.com/cn-app-web/identity-code/index.html#/")!
        let embedded = URL(string: "https://login.m.taobao.com/login.htm?ttid=h5%40iframe&redirectURL=https%3A%2F%2Fh5.m.taobao.com%2Fother%2Floginend.html&lang=zh_CN")!
        let result = try XCTUnwrap(LoginNavigation.topLevelLogin(embedded, returningTo: destination))
        let query = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.filter { $0.name.lowercased() == "redirecturl" }.map(\.value), [destination.absoluteString])
        XCTAssertFalse(query.contains { $0.name == "ttid" })
        XCTAssertEqual(query.first { $0.name == "lang" }?.value, "zh_CN")
    }

    func testDropsConflictingReturnParameters() throws {
        let destination = URL(string: "https://page.cainiao.com/guoguo/app-myexpress-taobao/")!
        let embedded = URL(string: "https://cnlogin.cainiao.com/login?redirectURL=old&returnUrl=other&redirectType=iframe&cnSite=CAINIAO2C")!
        let result = try XCTUnwrap(LoginNavigation.topLevelLogin(embedded, returningTo: destination))
        let query = URLComponents(url: result, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.count, 2)
        XCTAssertEqual(query.first { $0.name == "cnSite" }?.value, "CAINIAO2C")
        XCTAssertEqual(query.first { $0.name == "redirectURL" }?.value, destination.absoluteString)
    }

    func testRejectsLookalikeDomainsAndNonHTTPSCallbacks() {
        let valid = URL(string: "https://page.cainiao.com/cn-app-web/profile/index.html")!
        for raw in ["https://login.m.taobao.com.evil.test/login.htm",
                    "http://login.m.taobao.com/login.htm",
                    "https://name:password@login.m.taobao.com/login.htm",
                    "https://login.m.taobao.com:8443/login.htm",
                    "https://login.m.taobao.com/other/resource.js"] {
            XCTAssertNil(LoginNavigation.topLevelLogin(URL(string: raw)!, returningTo: valid))
        }
        XCTAssertNil(LoginNavigation.topLevelLogin(
            URL(string: "https://login.m.taobao.com/login.htm")!, returningTo: URL(string: "https://unrelated.test/")!
        ))
    }

    func testExplicitLoginPreservesDestinationQueryAndFragment() {
        let destination = URL(string: "https://page.cainiao.com/path?one=a%26b&two=2#/profile")!
        let result = LoginNavigation.loginURL(returningTo: destination)
        let query = URLComponents(url: result, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "redirectURL" }?.value, destination.absoluteString)
    }
}
