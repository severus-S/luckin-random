import XCTest
@testable import QuXCore

final class CainiaoLoginTests: XCTestCase {
    let login = CainiaoLogin(state: "synthetic-attempt-state-123456")

    func testEntryUsesCainiaoTenantAndOwnReturn() throws {
        XCTAssertEqual(login.loginURL.host, "cnlogin.cainiao.com")
        XCTAssertEqual(login.loginURL.path, "/login")
        let items = URLComponents(url: login.loginURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "cnSite" }?.value, "CAINIAO2C")
        XCTAssertEqual(items.first { $0.name == "redirectURL" }?.value, login.returnURL.absoluteString)
        XCTAssertTrue(login.isReturn(login.returnURL))
        XCTAssertFalse(CainiaoLogin().isReturn(login.returnURL))
    }

    func testSSORequiresOwnTenantTicketAndReturn() {
        var parts = URLComponents(string: "https://cnlogin.cainiao.com/doSsoLogin")!
        parts.queryItems = [URLQueryItem(name: "st", value: "synthetic-ticket-123456"),
                            URLQueryItem(name: "stSite", value: "78"), URLQueryItem(name: "cnSite", value: "CAINIAO2C"),
                            URLQueryItem(name: "redirectURL", value: login.returnURL.absoluteString)]
        XCTAssertTrue(login.ownsSSO(parts.url!))
        XCTAssertFalse(CainiaoLogin().ownsSSO(parts.url!))
        let original = parts.queryItems!
        parts.queryItems!.append(URLQueryItem(name: "st", value: "duplicate-ticket-123456"))
        XCTAssertFalse(login.ownsSSO(parts.url!))
        parts.queryItems = original.map { $0.name == "stSite" ? URLQueryItem(name: "stSite", value: "0") : $0 }
        XCTAssertFalse(login.ownsSSO(parts.url!))
        parts.queryItems = original
        parts.host = "cnlogin.cainiao.com.evil.test"
        XCTAssertFalse(login.ownsSSO(parts.url!))
    }

    func testReturnRejectsDuplicateStateAndNonHTTPS() {
        var parts = URLComponents(url: login.returnURL, resolvingAgainstBaseURL: false)!
        parts.queryItems!.append(URLQueryItem(name: "auth_state", value: login.state))
        XCTAssertFalse(login.isReturn(parts.url!))
        parts = URLComponents(url: login.returnURL, resolvingAgainstBaseURL: false)!
        parts.scheme = "http"
        XCTAssertFalse(login.isReturn(parts.url!))
    }

    func testAccountValidationRequiresSuccessfulBusinessReply() {
        func response(_ nick: String, code: String = "SUCCESS::调用成功") -> [String: Any] {
            ["ret": [code], "data": ["data": ["header": ["data": ["data": ["nick": nick]]]]]]
        }
        XCTAssertTrue(CainiaoLogin.hasBusinessSession(response("合成测试用户")))
        XCTAssertFalse(CainiaoLogin.hasBusinessSession(response("请登录")))
        XCTAssertFalse(CainiaoLogin.hasBusinessSession(response(" ")))
        XCTAssertFalse(CainiaoLogin.hasBusinessSession(response("合成测试用户", code: "FAIL_SYS_SESSION_EXPIRED")))
        XCTAssertFalse(CainiaoLogin.hasBusinessSession(["ret": ["SUCCESS"], "data": [:]]))
    }

    func testSigningBootstrapMatchesAPKUndefTokenAndRetries() {
        XCTAssertEqual(CainiaoLogin.signingToken(nil), "undefined")
        XCTAssertEqual(CainiaoLogin.signingToken(""), "undefined")
        XCTAssertEqual(CainiaoLogin.signingToken("synthetic_1234"), "synthetic")
        for code in ["FAIL_SYS_TOKEN_EXOIRED", "FAIL_SYS_TOKEN_EXPIRED", "FAIL_SYS_TOKEN_EMPTY", "FAIL_SYS_TOKEN_INVALID"] {
            XCTAssertTrue(CainiaoLogin.shouldRetryToken(code))
        }
        XCTAssertFalse(CainiaoLogin.shouldRetryToken("FAIL_SYS_SESSION_EXPIRED"))
    }

    func testDiagnosticsDistinguishSchemaFromServerFailureWithoutLeakingValues() {
        XCTAssertEqual(CainiaoLogin.diagnosticCode(["ret": ["FAIL_SYS_SESSION_EXPIRED::private details"]]), "FAIL_SYS_SESSION_EXPIRED")
        XCTAssertEqual(CainiaoLogin.diagnosticCode(["ret": ["SUCCESS::private details"]]), "ACCOUNT_SCHEMA_UNCONFIRMED")
        XCTAssertEqual(CainiaoLogin.diagnosticCode(["ret": ["https://private.test/?token=secret"]]), "INVALID_RESPONSE")
        XCTAssertEqual(CainiaoLogin.diagnosticCode([:]), "INVALID_RESPONSE")
    }
}
