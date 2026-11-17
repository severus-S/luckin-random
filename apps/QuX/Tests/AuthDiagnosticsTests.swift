import XCTest
@testable import QuXCore

final class AuthDiagnosticsTests: XCTestCase {
    func testDiagnosticsWhitelistNeverEchoesExtraPayload() {
        let body: [String: Any] = ["event": "request-end", "kind": "login", "status": 200,
                                   "phone": "PRIVATE", "token": "PRIVATE", "body": "PRIVATE"]
        XCTAssertEqual(AuthDiagnostics.line(host: "login.m.taobao.com", mainFrame: false, body: body),
                       "内嵌页面 login.m.taobao.com · request-end · login · HTTP 200")
        XCTAssertNil(AuthDiagnostics.line(host: "evil.test", mainFrame: false, body: body))
        XCTAssertNil(AuthDiagnostics.line(host: "login.m.taobao.com", mainFrame: false, body: ["event": "PRIVATE"]))
    }
}
