import XCTest
@testable import HairCore

final class HairCoreTests: XCTestCase {
    func decode(_ text: String) throws -> JSON { try JSONDecoder().decode(JSON.self, from: Data(text.utf8)) }
    func testOfficialIdentifiersAreExtractedWithoutNavigating() throws {
        XCTAssertEqual(try HairPolicy.scanParameters("https://h5.qiekj.com/skip?NQT=abc-123&advert=anything"), ["NQT": "abc-123"])
        XCTAssertEqual(try HairPolicy.scanParameters("https://example.test/?SN=abc?IMEI=123456789012345"), ["SN": "abc", "IMEI": "123456789012345"])
    }
    func testEncodedIdentifiersDecodeOnce() throws {
        XCTAssertEqual(try HairPolicy.scanParameters("https://h5.qiekj.com/?NQT=abc%2Ddef"), ["NQT": "abc-def"])
        XCTAssertThrowsError(try HairPolicy.scanParameters("https://h5.qiekj.com/?NQT=a%26token%3Dsecret"))
    }
    func testUnrecognizedAndAmbiguousCodesAreRefused() {
        for value in ["", "12345", "javascript:alert(1)", "https://example.test/", "https://x/?NQT=1&NQT=2", "https://x/?NQT=1\n", "https://x/?NQT=" ] { XCTAssertThrowsError(try HairPolicy.scanParameters(value)) }
    }
    func testMiniProgramIdentityAndPageAreFixed() throws {
        let url = try HairPolicy.miniProgramURL(["NQT": "abc"])
        XCTAssertEqual(url.scheme, "alipays")
        XCTAssertEqual(url.host, "platformapi")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "appId" }?.value, "2018072460764274")
        XCTAssertEqual(items.first { $0.name == "page" }?.value, "pages/skipNew/skipNew")
        let nested = items.first { $0.name == "query" }!.value!
        let params = URLComponents(string: "https://placeholder.invalid/?" + nested)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "NQT" }?.value, "abc")
        XCTAssertEqual(params.first { $0.name == "keepUsing" }?.value, "1")
    }
    func testScannedKeysCannotChangePaymentDestination() {
        XCTAssertThrowsError(try HairPolicy.miniProgramURL(["appId": "evil"]))
        XCTAssertThrowsError(try HairPolicy.miniProgramURL([:]))
    }
    func testOnlyHairDryerCategoryIsAccepted() throws {
        XCTAssertTrue(HairPolicy.isHairDevice(try decode("{\"categoryCode\":\"03\"}"), type: "goods"))
        for category in ["00", "01", "02", "05", "08", "0301"] { XCTAssertFalse(HairPolicy.isHairDevice(try decode("{\"categoryCode\":\"\(category)\"}"), type: "goods")) }
        XCTAssertFalse(HairPolicy.isHairDevice(.null, type: "goods"))
        XCTAssertFalse(HairPolicy.isHairDevice(try decode("{\"categoryCode\":\"03\"}"), type: "unknown"))
    }
    func testLegacyHairDryerIDIsRecognized() throws {
        XCTAssertTrue(HairPolicy.isHairDevice(try decode("{\"parentTypeId\":\"\(HairPolicy.legacyHairID)\"}"), type: "machine"))
        XCTAssertFalse(HairPolicy.isHairDevice(try decode("{\"parentTypeId\":\"washer\"}"), type: "machine"))
    }
    func testOrderFilteringDoesNotUseDeviceNameGuess() throws {
        XCTAssertTrue(HairPolicy.isHairOrder(try decode("{\"parentTypeId\":\"\(HairPolicy.legacyHairID)\"}")))
        XCTAssertTrue(HairPolicy.isHairOrder(try decode("{\"tradeOrderItem\":[{\"goodsCategory\":\"03\"}]}")))
        XCTAssertFalse(HairPolicy.isHairOrder(try decode("{\"name\":\"吹风机\",\"categoryCode\":\"00\"}")))
        XCTAssertFalse(HairPolicy.isHairOrder(.null))
    }
    func testInvalidOrderResponseIsNotEmptyList() throws {
        XCTAssertEqual(try HairPolicy.orderRows(decode("{\"items\":[]}")), [])
        for raw in ["{}", "null", "{\"items\":null}"] { XCTAssertThrowsError(try HairPolicy.orderRows(decode(raw))) }
    }
    func testEnvelopeRequiresSuccessfulCodeAndData() throws {
        XCTAssertEqual(try HairPolicy.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: 200), .array([]))
        for raw in ["{}", "{\"data\":[]}", "{\"code\":1,\"data\":[]}", "{\"code\":0}", "<html>error</html>"] { XCTAssertThrowsError(try HairPolicy.unwrap(Data(raw.utf8), status: 200)) }
        for status in [301, 401, 403, 500] { XCTAssertThrowsError(try HairPolicy.unwrap(Data("{\"code\":0,\"data\":[]}".utf8), status: status)) }
    }
    func testErrorNeverReflectsServerCredentialText() {
        XCTAssertThrowsError(try HairPolicy.unwrap(Data("{\"code\":1,\"msg\":\"token=private-value\"}".utf8), status: 200)) { XCTAssertFalse($0.localizedDescription.contains("private-value")) }
    }
    func testRequestOriginAndFormEncoding() throws {
        let request = try HairPolicy.request("goods/scan/v2", method: "POST", values: ["NQT": "abc"], token: "fixture+credential")
        XCTAssertEqual(request.url?.host, "userapi.qiekj.com")
        XCTAssertEqual(request.url?.path, "/goods/scan/v2")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(String(data: request.httpBody!, encoding: .utf8)!.contains("token=fixture%2Bcredential"))
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testOnlyDocumentedReadEndpointsAreAvailable() {
        for path in ["trade/create", "pay/preBalance", "machine/boot", "https://evil.test", "../user/info", "user/info?token=x"] { XCTAssertThrowsError(try HairPolicy.request(path, method: "POST", token: "fixture")) }
    }
    func testLoginNavigationExcludesMarketingAndOtherDevices() {
        XCTAssertTrue(HairPolicy.loginPaths.contains("/login"))
        XCTAssertTrue(HairPolicy.loginPaths.contains("/user/UserAgreement/userPrivacy/legalPrivacy"))
        for path in ["/", "/buyGold", "/adActivity", "/pages/goodsWash/wash/wash", "/pages/chooseDryer/newBlower/newBlower"] { XCTAssertFalse(HairPolicy.loginPaths.contains(path)) }
    }
    func testPhoneIsMaskedAndMoneyUsesYuan() {
        XCTAssertEqual(HairPolicy.maskedPhone("13800000000"), "138****0000")
        XCTAssertEqual(HairPolicy.money(.number(4.5)), "¥4.50")
        XCTAssertEqual(HairPolicy.money(.null), "未读取")
    }
    func testLongStringOrderIDsRemainExact() throws {
        XCTAssertEqual(try decode("{\"orderNo\":\"0123456789012345678901\"}")["orderNo"].text, "0123456789012345678901")
        XCTAssertEqual(try decode("{\"id\":9223372036854775801}")["id"].text, "9223372036854775801")
    }
}
