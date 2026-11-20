import Foundation

enum JSON: Codable, Equatable {
    case object([String: JSON]), array([JSON]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSON].self) { self = .object(v) }
        else { self = .array(try c.decode([JSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSON { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return NSDecimalNumber(decimal: n).stringValue
        default: return ""
        }
    }
    var integer: Int? { Int(text) }
    var flag: Bool { self == .bool(true) || integer == 1 }
    var list: [JSON] { if case .array(let v) = self { return v }; return [] }
    var fields: [String: JSON] { if case .object(let v) = self { return v }; return [:] }
    func firstText(_ keys: String...) -> String { keys.map { self[$0].text }.first { !$0.isEmpty } ?? "" }
}


struct HairError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum HairPolicy {
    static let legacyHairID = "4eeb1b0a-d006-49cc-bf17-73c20599057b"
    static let origin = URL(string: "https://userapi.qiekj.com/")!
    static let loginURL = URL(string: "https://h5.qiekj.com/login?disabledQiYu=1")!
    static let idlePath = "/__pghair__"
    static let loginPaths: Set<String> = ["/login", idlePath, "/user/UserAgreement/UserAgreement", "/user/UserAgreement/newUserAgreement", "/user/UserAgreement/userPrivacy/legalPrivacy", "/user/privacyPolicy/privacyPolicy", "/user/privacyPolicy/newPrivacyPolicy", "/user/UserAgreement/userPrivacy/thirdSharing", "/user/UserAgreement/userPrivacy/systemRight", "/user/UserAgreement/userPrivacy/mansCollection"]
    static let apiPaths: Set<String> = ["user/info", "goods/scan/v2", "goods/normal/details", "machine/detail", "order/list"]
    static func scanParameters(_ raw: String) throws -> [String: String] {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard (1...4096).contains(s.count), !s.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { throw HairError(message: "二维码内容无效。") }
        // Official scanCodeInit extracts these three identifiers; the scanned URL is never opened.
        guard let u = URLComponents(string: s), ["https", "http"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { throw HairError(message: "暂不支持这种码，请扫描胖乖生活吹风机的完整二维码。") }
        let tail = s.contains("?") ? String(s[s.index(after: s.firstIndex(of: "?")!)...]).replacingOccurrences(of: "?", with: "&") : ""
        let q = URLComponents(string: "https://placeholder.invalid/?" + tail)?.queryItems ?? []
        var output: [String: String] = [:]
        for key in ["NQT", "SN", "IMEI"] {
            let values = q.filter { $0.name == key }.compactMap(\.value)
            guard values.count <= 1 else { throw HairError(message: "二维码中设备标识重复，请重新扫描。") }
            if let value = values.first, !value.isEmpty {
                guard value.count <= 256, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else { throw HairError(message: "二维码中的设备标识格式不正确。") }
                output[key] = value
            }
        }
        guard !output.isEmpty else { throw HairError(message: "二维码缺少胖乖设备标识（NQT、SN 或 IMEI）。") }
        return output
    }
    static func miniProgramURL(_ params: [String: String]) throws -> URL {
        guard !params.isEmpty, Set(params.keys).isSubset(of: ["NQT", "SN", "IMEI"]) else { throw HairError(message: "缺少已识别的吹风机二维码。") }
        var nested = URLComponents()
        nested.queryItems = [URLQueryItem(name: "keepUsing", value: "1")] + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var link = URLComponents(string: "alipays://platformapi/startapp")!
        link.queryItems = [URLQueryItem(name: "appId", value: "2018072460764274"), URLQueryItem(name: "page", value: "pages/skipNew/skipNew"), URLQueryItem(name: "query", value: nested.percentEncodedQuery)]
        return link.url!
    }
    static func isHairDevice(_ info: JSON, type: String) -> Bool {
        if type == "goods" { return info["categoryCode"].text == "03" }
        if type == "machine" { return info["parentTypeId"].text == legacyHairID || info["typeId"].text == legacyHairID }
        return false
    }
    static func isHairOrder(_ row: JSON) -> Bool {
        if row["parentTypeId"].text == legacyHairID || row["categoryCode"].text == "03" { return true }
        return row["tradeOrderItem"].list.contains { item in
            let category = item["goodsCategory"].text
            return item["categoryCode"].text == "03" || category == "03"
        }
    }
    static func orderRows(_ data: JSON) throws -> [JSON] {
        guard case .array(let rows) = data["items"] else { throw HairError(message: "订单数据格式变化，未把异常响应当成空订单。") }
        return rows
    }
    static func unwrap(_ data: Data, status: Int) throws -> JSON {
        guard status == 200 else { throw HairError(message: "服务请求未完成（HTTP \(status)）。") }
        let value = try? JSONDecoder().decode(JSON.self, from: data)
        guard let value, value["code"].integer == 0 else {
            let code = value?["code"].integer
            throw HairError(message: "服务端未完成请求（代码 \(code.map(String.init) ?? "UNKNOWN")）。请检查登录或设备状态。")
        }
        guard value.fields.keys.contains("data") else { throw HairError(message: "服务响应缺少数据。") }
        return value["data"]
    }
    static func request(_ path: String, method: String, values: [String: String] = [:], token: String) throws -> URLRequest {
        guard apiPaths.contains(path), ["GET", "POST"].contains(method) else { throw HairError(message: "此操作不在精简版功能范围内。") }
        var form = values
        form["token"] = token
        var parts = URLComponents(url: origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var r = URLRequest(url: parts.url!, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("IPHONE", forHTTPHeaderField: "phoneBrand")
        r.setValue("https://h5.qiekj.com", forHTTPHeaderField: "Origin")
        r.setValue("https://h5.qiekj.com/", forHTTPHeaderField: "Referer")
        r.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 PGHair/0.1", forHTTPHeaderField: "User-Agent")
        if method == "GET" { parts.queryItems = items; r.url = parts.url }
        else {
            var body = URLComponents(); body.queryItems = items
            r.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        }
        return r
    }
    static func maskedPhone(_ s: String) -> String {
        guard s.count == 11 else { return s.isEmpty ? "账号未确认" : "已登录账号" }
        return String(s.prefix(3)) + "****" + String(s.suffix(4))
    }
    static func money(_ data: JSON) -> String {
        guard let n = Decimal(string: data.text), n >= 0 else { return "未读取" }
        return "¥" + String(format: "%.2f", NSDecimalNumber(decimal: n).doubleValue)
    }
}
