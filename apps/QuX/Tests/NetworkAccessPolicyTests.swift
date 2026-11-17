import XCTest
@testable import QuXCore

final class NetworkAccessPolicyTests: XCTestCase {
    func testWebBrowsingDoesNotRestrictHostOrHTTP() {
        for raw in ["http://unrelated.example/path", "https://another.example/path", "about:blank", "blob:https://example.test/id", "data:text/plain,example"] {
            XCTAssertTrue(NetworkAccessPolicy.isWebKitURL(URL(string: raw)!))
        }
        for raw in ["tbopen://m.taobao.com/", "taobao://example", "cainiao://example", "alipays://example"] {
            XCTAssertFalse(NetworkAccessPolicy.isWebKitURL(URL(string: raw)!))
        }
    }
    func testRedirectsFollowWithoutLeakingCredentialsAcrossOrigins() {
        let previous = URL(string: "https://acs.m.taobao.com/h5/test")!
        var proposed = URLRequest(url: URL(string: "https://acs.m.taobao.com/next")!)
        proposed.setValue("synthetic-cookie", forHTTPHeaderField: "Cookie")
        proposed.setValue("synthetic-auth", forHTTPHeaderField: "Authorization")
        XCTAssertEqual(NetworkAccessPolicy.redirectedRequest(proposed, from: previous).value(forHTTPHeaderField: "Cookie"), "synthetic-cookie")
        for target in ["https://another.example/next", "http://acs.m.taobao.com/next", "https://acs.m.taobao.com:8443/next"] {
            proposed.url = URL(string: target)!
            let result = NetworkAccessPolicy.redirectedRequest(proposed, from: previous)
            XCTAssertEqual(result.url, proposed.url)
            XCTAssertNil(result.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(result.value(forHTTPHeaderField: "Authorization"))
        }
    }
}
