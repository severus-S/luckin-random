import XCTest
@testable import UWashCore

final class LaundryCoreTests: XCTestCase {
    private func json(_ s: String) throws -> JSON { try JSONDecoder().decode(JSON.self, from: Data(s.utf8)) }
    private let deviceQR = "0000DA9934800000317A259900050000"
    func testLargeOrderIDRemainsExact() throws {
        let value = try json("{\"orderId\":9223372036854775801}")
        XCTAssertEqual(value["orderId"].text, "9223372036854775801")
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(value)), value)
    }
    func testOnlySuccessfulEnvelopeCommitsData() throws {
        XCTAssertEqual(try LaundryProtocol.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: 200), .array([]))
        for raw in ["{}", "{\"data\":[]}", "{\"code\":1,\"data\":[]}", "{\"code\":0}", "<html>error</html>"] { XCTAssertThrowsError(try LaundryProtocol.unwrap(Data(raw.utf8), status: 200)) }
    }
    func testAuthenticationAndHTTPFailuresDoNotReturnEmptyOrders() {
        for status in [302, 401, 403, 404, 500] { XCTAssertThrowsError(try LaundryProtocol.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: status)) }
    }
    func testErrorDoesNotReflectServerSecrets() {
        for body in ["{\"code\":123,\"message\":\"token=secret123\"}", "{\"code\":\"secret123\",\"message\":\"private\"}"] {
            XCTAssertThrowsError(try LaundryProtocol.unwrap(Data(body.utf8), status: 200)) { XCTAssertFalse($0.localizedDescription.contains("secret123")) }
        }
    }
    func testScanRequestAndFixedAPIOrigin() throws {
        let body: JSON = .object(["qrCode": .string(deviceQR)])
        let request = try LaundryProtocol.request(path: "devices/scanWasherCode", method: "POST", body: body, token: "fixture-secret")
        XCTAssertEqual(request.url?.host, "phoenix.ujing.online")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: XCTUnwrap(request.httpBody)), body)
    }
    func testOfficialNestedScanEnvelopeReachesMatchingWasher() throws {
        let response = Data("{\"code\":0,\"data\":{\"result\":{\"deviceId\":9223372036854775801,\"createOrderEnabled\":true,\"moduleType\":7}}}".utf8)
        let data = try LaundryProtocol.unwrap(response, status: 200)
        XCTAssertTrue(data["deviceId"].text.isEmpty, "The old parser read this wrong level")
        guard case .device(let id) = try LaundryProtocol.scanTarget(data) else { return XCTFail("Expected washer") }
        XCTAssertEqual(id, "9223372036854775801")
        let request = try LaundryProtocol.request(path: "app/washer/devices/program/info", query: ["deviceId": id], token: "fixture")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, id)
        let device = try LaundryProtocol.washerDevice(json("{\"deviceId\":9223372036854775801,\"type\":1}"), expectedID: id)
        XCTAssertEqual(device["deviceId"].text, id)
    }
    func testStringDeviceIDFromNestedScanResult() throws {
        XCTAssertEqual(try LaundryProtocol.scanTarget(json("{\"result\":{\"deviceId\":\"washer-abc_123\",\"createOrderEnabled\":true}}")), .device("washer-abc_123"))
    }
    func testExistingOrderIsNotTreatedAsMissingDeviceID() throws {
        let data = try json("{\"result\":{\"createOrderEnabled\":false,\"orderId\":9223372036854775801}}")
        XCTAssertEqual(try LaundryProtocol.scanTarget(data), .existingOrder("9223372036854775801"))
    }
    func testUnavailableDeviceDoesNotReportIdentifierFormat() throws {
        let data = try json("{\"result\":{\"createOrderEnabled\":false,\"reason\":\"private-mobile\"}}")
        XCTAssertThrowsError(try LaundryProtocol.scanTarget(data)) {
            XCTAssertTrue($0.localizedDescription.contains("当前不可使用"))
            XCTAssertFalse($0.localizedDescription.contains("编号格式"))
            XCTAssertFalse($0.localizedDescription.contains("private-mobile"))
        }
    }
    func testMalformedScanResultDoesNotReachDeviceRequest() throws {
        for raw in ["null", "{}", "{\"deviceId\":123,\"createOrderEnabled\":true}", "{\"result\":null}", "{\"result\":[]}", "{\"result\":{}}", "{\"result\":{\"createOrderEnabled\":true}}", "{\"result\":{\"createOrderEnabled\":\"true\",\"deviceId\":123}}", "{\"result\":{\"createOrderEnabled\":true,\"deviceId\":\"../123\"}}", "{\"result\":{\"createOrderEnabled\":false,\"orderId\":\"../123\"}}"] {
            XCTAssertThrowsError(try LaundryProtocol.scanTarget(json(raw)), raw)
        }
    }
    func testWasherDetailMustMatchScannedDevice() throws {
        let device = try json("{\"deviceId\":123,\"type\":1}")
        XCTAssertNoThrow(try LaundryProtocol.washerDevice(device, expectedID: "123"))
        XCTAssertThrowsError(try LaundryProtocol.washerDevice(device, expectedID: "456"))
    }
    func testReadOnlyRequestsKeepTokenInHeader() throws {
        let request = try LaundryProtocol.request(path: "orders/history", query: ["page": "1", "size": "20"], token: "fixture-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-secret")
        XCTAssertFalse(request.url!.absoluteString.contains("fixture-secret"))
        XCTAssertNil(request.httpBody)
    }
    func testNativeOrderPaymentAndControlEndpointsAreDisabled() {
        for (path, method) in [("orders/create", "POST"), ("payment/arguments", "GET"), ("payment/methods", "GET"), ("orders/123/control/start", "GET"), ("orders/123/control/stop", "GET"), ("orders/123/cancel", "POST"), ("login", "POST")] {
            XCTAssertThrowsError(try LaundryProtocol.request(path: path, method: method, token: "fixture"), "Native operation still allowed: \(path)")
        }
    }
    func testOnlyOrderDetailReadsAreAllowed() throws {
        XCTAssertEqual(try LaundryProtocol.request(path: "orders/123/detail", token: "fixture").url?.path, "/api/v1/orders/123/detail")
        XCTAssertThrowsError(try LaundryProtocol.request(path: "orders/123/detail", method: "POST", token: "fixture"))
        XCTAssertThrowsError(try LaundryProtocol.request(path: "orders/123/detail", body: .object([:]), token: "fixture"))
    }
    func testRefusesPathInjection() {
        for path in ["https://evil.test", "../users", "/users", "orders?token=bad", "orders#fragment"] { XCTAssertThrowsError(try LaundryProtocol.request(path: path, token: "fixture")) }
        for id in ["", "../123", "123/pay", "1?x=2", "x\n"] { XCTAssertThrowsError(try LaundryProtocol.identifier(id)) }
    }
    func testLegacyWasherQRIsPreserved() throws {
        XCTAssertEqual(try LaundryProtocol.handoffQRCode("  \(deviceQR)  "), deviceQR)
        XCTAssertThrowsError(try LaundryProtocol.handoffQRCode("123456"))
        XCTAssertThrowsError(try LaundryProtocol.handoffQRCode("account-token-is-not-a-washer-code"))
    }
    func testOfficialURLIsPreserved() throws {
        let raw = "https://wx.zhinengxiyifang.cn/?qrcode=A%2BB%2FC%3D&device=1#machine"
        XCTAssertEqual(try LaundryProtocol.handoffQRCode(raw), raw)
        XCTAssertEqual(try LaundryProtocol.handoffQRCode("http://s.zhinengxiyifang.cn/?qrcode=abc"), "http://s.zhinengxiyifang.cn/?qrcode=abc")
    }
    func testMalformedQRLinksAreRejected() {
        for raw in ["", "https://user:password@wx.zhinengxiyifang.cn/", "https://wx.zhinengxiyifang.cn:4443/", "file:///etc/passwd", "alipays://platformapi/startapp?appId=bad", "https://wx.zhinengxiyifang.cn/?qrcode=a\n", String(repeating: "a", count: 4097)] {
            XCTAssertThrowsError(try LaundryProtocol.handoffQRCode(raw))
        }
    }
    func testScannedHostCannotBecomeNavigationTarget() throws {
        let url = try LaundryProtocol.alipayMiniProgramURL(qrCode: "https://unknown-qr.example/device/123")
        XCTAssertEqual(url.scheme, "alipays")
        XCTAssertEqual(url.host, "platformapi")
        XCTAssertEqual(url.path, "/startapp")
    }
    func testAccountLinksAreNotForwardedAsDeviceCodes() {
        for query in ["token=private", "accessToken=private", "access_token=private", "%74oken=private", "mobile=13800000000", "ticket=private", "auth_code=private"] {
            XCTAssertThrowsError(try LaundryProtocol.alipayMiniProgramURL(qrCode: "https://wx.zhinengxiyifang.cn/?" + query))
        }
    }
    func testHomepageMatchesOfficialAPK() throws {
        let url = try LaundryProtocol.alipayMiniProgramURL()
        XCTAssertEqual(url.scheme, "alipays")
        XCTAssertEqual(url.host, "platformapi")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "appId" }?.value, "2021002174638299")
        XCTAssertEqual(items.first { $0.name == "page" }?.value, "pages/home/home")
        XCTAssertNil(items.first { $0.name == "query" })
    }
    func testExperimentalQRRoundTripThroughBothEncodingLayers() throws {
        let raw = "https://wx.zhinengxiyifang.cn/?qrcode=abc+def%2F123%3D&x=1#machine"
        let url = try LaundryProtocol.alipayMiniProgramURL(qrCode: raw)
        let outer = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let nested = outer.first { $0.name == "query" }!.value!
        XCTAssertTrue(nested.contains("%2B"))
        let inner = URLComponents(string: "https://placeholder.invalid/?" + nested)!.queryItems!
        XCTAssertEqual(inner.first { $0.name == "qrcode" }?.value, raw)
    }
    func testQRQueryCannotOverrideMiniProgramIdentity() throws {
        let raw = "https://wx.zhinengxiyifang.cn/?appId=evil&page=evil&qrcode=abc"
        let url = try LaundryProtocol.alipayMiniProgramURL(qrCode: raw)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.filter { $0.name == "appId" }.map(\.value), ["2021002174638299"])
        XCTAssertEqual(items.filter { $0.name == "page" }.map(\.value), ["pages/home/home"])
    }
    func testNativeReadsAndScanRequireOwnLogin() {
        XCTAssertThrowsError(try LaundryProtocol.request(path: "orders/running"))
        XCTAssertThrowsError(try LaundryProtocol.request(path: "devices/scanWasherCode", method: "POST", body: .object(["qrCode": .string(deviceQR)])))
        XCTAssertThrowsError(try LaundryProtocol.request(path: "app/washer/devices/program/info"))
    }
    func testDeviceReadOnlyForWasher() throws {
        XCTAssertNoThrow(try LaundryProtocol.washerDevice(json("{\"deviceId\":123,\"type\":1}")))
        for raw in ["{}", "{\"deviceId\":123}", "{\"deviceId\":123,\"type\":2}", "{\"type\":1}"] {
            XCTAssertThrowsError(try LaundryProtocol.washerDevice(json(raw)))
        }
        XCTAssertEqual(try LaundryProtocol.request(path: "app/washer/devices/program/info", query: ["deviceId": "123"], token: "fixture").httpMethod, "GET")
    }
    func testTokenOnlyReadOnOfficialLoginDocument() {
        XCTAssertTrue(LaundryProtocol.isLoginDocument(LaundryProtocol.loginURL))
        XCTAssertTrue(LaundryProtocol.isLoginDocument(URL(string: LaundryProtocol.loginPage + "#/__uwash__")!))
        for raw in ["http://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html#/login", "https://evil.test/static/washer-h5/commonWasher/latest/index.html#/login", LaundryProtocol.loginPage + "#/cashier/123", LaundryProtocol.loginPage + "#/home", "https://wx.zhinengxiyifang.cn/about_us/privacy_policy.html"] {
            XCTAssertFalse(LaundryProtocol.isLoginDocument(URL(string: raw)!))
        }
    }
    func testMalformedListIsNotEmptyList() throws {
        XCTAssertEqual(try LaundryProtocol.rows(json("{\"list\":[]}")), [])
        for raw in ["null", "{}", "{\"list\":null}", "{\"message\":\"empty\"}"] { XCTAssertThrowsError(try LaundryProtocol.rows(json(raw))) }
    }
    func testPricesAreCentsAndStatusesMatchAPK() throws {
        XCTAssertEqual(LaundryProtocol.money(.number(450)), "¥4.50")
        XCTAssertEqual(LaundryProtocol.money(.null), "价格待确认")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":30}")), "自洁中")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":35}")), "自洁完成")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":53}")), "订单已取消")
    }
}
