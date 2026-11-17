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
        XCTAssertEqual(query.count, 3)
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

    func testCurrentOfficialHavanaLoginCanLeaveTheWidgetFrame() throws {
        let destination = URL(string: "https://page.cainiao.com/cn-app-web/identity-code/index.html#/")!
        let login = URL(string: "https://login.m.taobao.com/havanaone/login/login.htm?bizName=taobao&redirectURL=old")!
        let promoted = try XCTUnwrap(LoginNavigation.topLevelLogin(login, returningTo: destination))
        let query = URLComponents(url: promoted, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "redirectURL" }?.value, destination.absoluteString)
        XCTAssertEqual(query.first { $0.name == "bizName" }?.value, "taobao")
    }

    func testUpgradesLegacyOfficialReturnWithoutLosingParameters() throws {
        let original = URL(string: "http://login.taobao.com:80/member/vst.htm?st=synthetic%2Bvalue&next=a%26b#done")!
        let upgraded = try XCTUnwrap(LoginNavigation.webFallback(original))
        XCTAssertEqual(upgraded.absoluteString, "https://login.taobao.com/member/vst.htm?st=synthetic%2Bvalue&next=a%26b#done")
        XCTAssertNil(LoginNavigation.webFallback(URL(string: "http://login.taobao.com:8080/a")!))
        XCTAssertNil(LoginNavigation.webFallback(URL(string: "http://login.taobao.com.evil.test/a")!))
        XCTAssertNil(LoginNavigation.webFallback(URL(string: "http://user:secret@login.taobao.com/a")!))
    }

    func testTaobaoAppCarrierContinuesAtItsOfficialWebDestination() throws {
        var carrier = URLComponents(string: "tbopen://m.taobao.com/tbopen/index.html")!
        let destination = "https://page.cainiao.com/guoguo/app-myexpress-taobao/?x=a%26b#/"
        carrier.queryItems = [URLQueryItem(name: "h5Url", value: destination)]
        XCTAssertEqual(LoginNavigation.webFallback(carrier.url!)?.absoluteString, destination)
        for target in ["https://evil.test/", "javascript:alert(1)", "tbopen://m.taobao.com/tbopen/index.html"] {
            carrier.queryItems = [URLQueryItem(name: "h5Url", value: target)]
            XCTAssertNil(LoginNavigation.webFallback(carrier.url!))
        }
        carrier.queryItems = [URLQueryItem(name: "h5Url", value: destination), URLQueryItem(name: "h5Url", value: destination)]
        XCTAssertNil(LoginNavigation.webFallback(carrier.url!))
    }

    func testBlockedDiagnosticsNeverIncludeLoginParameters() {
        let url = URL(string: "otherapp://user:secret@example.test/private?st=token#session")!
        XCTAssertEqual(LoginNavigation.blockedMessage(url), "无法继续此跳转（otherapp · example.test）。请将此提示反馈。")
    }

    func testLoginDisablesAppLaunchAndRemovesHigherPriorityLegacyReturn() {
        let destination = URL(string: "https://page.cainiao.com/guoguo/app-myexpress-taobao/")!
        let source = URL(string: "https://login.m.taobao.com/login.htm?tpl_redirect_url=old&hideCallApp=false")!
        let result = LoginNavigation.topLevelLogin(source, returningTo: destination)!
        let items = URLComponents(url: result, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "hideCallApp" }?.value, "true")
        XCTAssertFalse(items.contains { $0.name == "tpl_redirect_url" })
        XCTAssertEqual(items.first { $0.name == "redirectURL" }?.value, destination.absoluteString)
    }

    func testTmallInternationalSessionHandoffIsAllowedWithoutRewriting() {
        let handoff = URL(string: "https://pass.tmall.hk/add?synthetic=value%2B1&redirectURL=https%3A%2F%2Fpage.cainiao.com%2F")!
        XCTAssertTrue(LoginNavigation.allows(handoff))
        XCTAssertNil(LoginNavigation.webFallback(handoff))
        XCTAssertFalse(LoginNavigation.isLogin(handoff))
        XCTAssertNil(LoginNavigation.topLevelLogin(handoff, returningTo: cainiaoTestDestination))
        XCTAssertTrue(LoginNavigation.allows(URL(string: "https://PASS.TMALL.HK:443/add")!))
    }

    private var cainiaoTestDestination: URL { URL(string: "https://page.cainiao.com/guoguo/app-myexpress-taobao/")! }

    func testTmallHandoffRejectsLookalikesCredentialsAndUnexpectedPorts() {
        for raw in ["https://pass.tmall.hk.evil.test/add", "https://evilpass.tmall.hk/add",
                    "https://child.pass.tmall.hk/add", "https://unrelated.tmall.hk/add",
                    "http://pass.tmall.hk/add", "https://user:secret@pass.tmall.hk/add",
                    "https://pass.tmall.hk:8443/add"] {
            XCTAssertFalse(LoginNavigation.allows(URL(string: raw)!), raw)
        }
        XCTAssertEqual(LoginNavigation.webFallback(URL(string: "http://pass.tmall.hk/add?synthetic=a%26b")!)?.absoluteString,
                       "https://pass.tmall.hk/add?synthetic=a%26b")
    }
}
