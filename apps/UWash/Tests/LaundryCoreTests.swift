import XCTest
@testable import UWashCore

final class LaundryCoreTests: XCTestCase {
    private func json(_ s: String) throws -> JSON { try JSONDecoder().decode(JSON.self, from: Data(s.utf8)) }
    func testLargeOrderIDRemainsExact() throws {
        let value = try json("{\"orderId\":9223372036854775801}")
        XCTAssertEqual(value["orderId"].text, "9223372036854775801")
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(value)), value)
    }
    func testOnlySuccessfulEnvelopeCommitsData() throws {
        XCTAssertEqual(try LaundryProtocol.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: 200), .array([]))
        for raw in ["{}", "{\"data\":[]}", "{\"code\":1,\"data\":[]}", "{\"code\":0}", "<html>error</html>"] {
            XCTAssertThrowsError(try LaundryProtocol.unwrap(Data(raw.utf8), status: 200))
        }
    }
    func testAuthenticationAndHTTPFailuresDoNotReturnEmptyOrders() {
        for status in [302, 401, 403, 404, 500] { XCTAssertThrowsError(try LaundryProtocol.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: status)) }
    }
    func testFailureDoesNotReflectSensitiveServerText() {
        let body = Data("{\"code\":123,\"message\":\"token=secret123\"}".utf8)
        XCTAssertThrowsError(try LaundryProtocol.unwrap(body, status: 200)) { XCTAssertFalse($0.localizedDescription.contains("secret123")) }
    }
    func testQueryIsEncodedAndOriginFixed() throws {
        let request = try LaundryProtocol.request(path: "devices/scanWasherCode", method: "POST", body: .object(["qrCode": .string("https://example.com/?a=1&b=2")]), token: "fixture")
        XCTAssertEqual(request.url?.host, "phoenix.ujing.online")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-code"), "BI")
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: XCTUnwrap(request.httpBody))["qrCode"].text, "https://example.com/?a=1&b=2")
        let query = try LaundryProtocol.request(path: "orders/history", query: ["value": "a&b=中"])
        XCTAssertEqual(URLComponents(url: query.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b=中")
    }
    func testRefusesPathInjection() {
        for path in ["https://evil.test", "../users", "/users", "orders?token=bad", "orders#fragment"] { XCTAssertThrowsError(try LaundryProtocol.request(path: path)) }
        for id in ["", "../123", "123/pay", "1?x=2", "x\n"] { XCTAssertThrowsError(try LaundryProtocol.identifier(id)) }
    }
    func testQRIsNotRewrittenOrNavigated() throws {
        let raw = "https://wx.zhinengxiyifang.cn/?id=123&k=abc"
        XCTAssertEqual(try LaundryProtocol.qrCode("  \(raw)  "), raw)
        XCTAssertThrowsError(try LaundryProtocol.qrCode(""))
        XCTAssertThrowsError(try LaundryProtocol.qrCode("qr\ncode"))
    }
    func testMalformedListIsNotEmptyList() throws {
        XCTAssertEqual(try LaundryProtocol.rows(json("{\"list\":[]}")), [])
        for raw in ["null", "{}", "{\"list\":null}", "{\"message\":\"empty\"}"] { XCTAssertThrowsError(try LaundryProtocol.rows(json(raw))) }
    }
    func testBluetoothDevicesCannotCreateOrders() throws {
        let program = try json("{\"workModelId\":18}")
        for module in [1, 4, 5] {
            let device = try json("{\"type\":1,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4,\"moduleType\":\(module)}")
            XCTAssertThrowsError(try LaundryProtocol.orderBody(device: device, program: program, extras: [:]))
        }
    }
    func testOrderUsesServerModelIDAndDoesNotAcceptPrice() throws {
        let d = try json("{\"type\":1,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4,\"moduleType\":2}")
        let p = try json("{\"workModelId\":18,\"basePrice\":400}")
        let body = try LaundryProtocol.orderBody(device: d, program: p, extras: [:])
        XCTAssertEqual(body["deviceWashModelId"].text, "18")
        XCTAssertNil(body.fields["price"])
        XCTAssertEqual(body.fields.count, 5)
        XCTAssertThrowsError(try LaundryProtocol.orderBody(device: .null, program: p, extras: [:]))
        XCTAssertThrowsError(try LaundryProtocol.orderBody(device: d, program: p, extras: ["price": .number(1)]))
    }
    func testStoreOrderBlockIsRespected() throws {
        let d = try json("{\"type\":1,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4,\"moduleType\":2,\"notification\":{\"usageLimit\":1}}")
        XCTAssertThrowsError(try LaundryProtocol.orderBody(device: d, program: json("{\"workModelId\":18}"), extras: [:]))
    }
    func testForcedAddOnMustBeValidServerOption() throws {
        let d = try json("{\"type\":1,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4,\"moduleType\":2,\"isForceDetergent\":true}")
        let p = try json("{\"workModelId\":18,\"additionDevices\":{\"washingPartnerFeature\":[{\"key\":\"wp_detergentGearId\",\"options\":[{\"id\":9}]}]}}")
        XCTAssertThrowsError(try LaundryProtocol.orderBody(device: d, program: p, extras: [:]))
        XCTAssertThrowsError(try LaundryProtocol.orderBody(device: d, program: p, extras: ["wp_detergentGearId": .number(99)]))
        XCTAssertEqual(try LaundryProtocol.orderBody(device: d, program: p, extras: ["wp_detergentGearId": .number(9)])["wp_detergentGearId"], .number(9))
    }
    func testPaymentNavigationDoesNotAcceptArbitrarySites() {
        XCTAssertNotNil(LaundryProtocol.paymentURL("https://mapi.alipay.com/pay?a=1"))
        XCTAssertNotNil(LaundryProtocol.paymentURL("alipays://platformapi/startapp"))
        for value in ["https://alipay.com.evil.test", "https://u:p@alipay.com", "http://alipay.com", "file:///etc/passwd", "javascript:alert(1)", "https://example.com"] { XCTAssertNil(LaundryProtocol.paymentURL(value)) }
    }
    func testPricesAreCents() {
        XCTAssertEqual(LaundryProtocol.money(.number(450)), "¥4.50")
        XCTAssertEqual(LaundryProtocol.money(.null), "价格待确认")
    }
    func testUnknownModulesAndDryersDoNotCreateWashOrders() throws {
        let program = try json("{\"workModelId\":18}")
        for raw in ["{\"type\":1,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4}", "{\"type\":2,\"deviceTypeId\":2,\"deviceId\":3,\"storeId\":4,\"moduleType\":2}"] {
            XCTAssertThrowsError(try LaundryProtocol.orderBody(device: json(raw), program: program, extras: [:]))
        }
    }
    func testWasherStatusesMatchAPK() throws {
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":30}")), "自洁中")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":35}")), "自洁完成")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":53}")), "订单已取消")
        XCTAssertEqual(LaundryProtocol.status(try json("{\"status\":60}")), "故障中")
    }
}
