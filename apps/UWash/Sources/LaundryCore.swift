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

struct LaundryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum LaundryProtocol {
    static let base = URL(string: "https://phoenix.ujing.online/api/v1/")!
    static let apiVersion = "2.4.15"
    static func unwrap(_ data: Data, status: Int) throws -> JSON {
        let value = try? JSONDecoder().decode(JSON.self, from: data)
        if status == 401 || status == 403 { throw LaundryError(message: "登录已失效，请重新登录（HTTP \(status)）。") }
        guard status == 200 else { throw LaundryError(message: "服务暂不可用（HTTP \(status)），请稍后重试。") }
        guard let value, value["code"].integer == 0 else {
            let code = value?["code"].integer.map(String.init) ?? "UNKNOWN"
            // Server text may contain credentials or reflected input. Keep diagnostics bounded and value-free.
            throw LaundryError(message: "服务端未完成请求（代码 \(code.prefix(20))）。请检查账号、设备状态后重试。")
        }
        guard value.fields.keys.contains("data") else { throw LaundryError(message: "服务端响应缺少数据，未更新本地状态。") }
        return value["data"]
    }
    static func request(path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil, token: String = "") throws -> URLRequest {
        guard !path.contains("://"), !path.contains(".."), !path.hasPrefix("/"), !path.contains("?"), !path.contains("#") else { throw LaundryError(message: "无效的接口地址。") }
        let pieces = path.split(separator: "/").map(String.init)
        let detail = pieces.count == 3 && pieces[0] == "orders" && pieces[2] == "detail" && (try? identifier(pieces[1])) != nil
        let read = method == "GET" && (path == "orders/running" || path == "orders/history" || detail || path == "app/washer/devices/program/info") && body == nil
        let scan = method == "POST" && path == "devices/scanWasherCode"
        guard read || scan else { throw LaundryError(message: "登录请使用官方网页；选择程序、下单、付款和设备操作请在 U净支付宝小程序完成。") }
        guard !token.isEmpty else { throw LaundryError(message: "请先完成 U净网页登录。") }
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var r = URLRequest(url: parts.url!, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("BI", forHTTPHeaderField: "x-app-code")
        r.setValue(apiVersion, forHTTPHeaderField: "x-app-version")
        r.setValue("1.1.75", forHTTPHeaderField: "weex-version")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = try JSONEncoder().encode(body) }
        return r
    }
    static func identifier(_ text: String) throws -> String {
        guard !text.isEmpty, text.count <= 100, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw LaundryError(message: "设备或订单编号格式不正确。") }
        return text
    }
    // The APK links this exact Ujing mini-program homepage. The qrcode query is
    // an experimental handoff inferred from Ujing's H5; recognition needs a phone test.
    static let alipayAppID = "2021002174638299"
    static let alipayHomePage = "pages/home/home"
    static let loginPage = "https://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html"
    static let loginURL = URL(string: loginPage + "#/login")!
    static func isLoginDocument(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "wx.zhinengxiyifang.cn", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil,
              url.path == "/static/washer-h5/commonWasher/latest/index.html" else { return false }
        let route = (url.fragment ?? "").components(separatedBy: "?").first ?? ""
        return ["/login", "/__uwash__"].contains(route)
    }
    static func washerDevice(_ info: JSON) throws -> JSON {
        guard !info["deviceId"].text.isEmpty, info["type"].integer == 1 else { throw LaundryError(message: "未确认这是洗衣机，本版只接入自助洗衣设备。") }
        return info
    }
    static func handoffQRCode(_ text: String) throws -> String {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard (1...4096).contains(s.count), !s.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { throw LaundryError(message: "二维码内容无效。") }
        // Ujing's legacy H5 also accepts a bare hexadecimal washer code.
        if (16...256).contains(s.count), s.allSatisfy({ $0.isASCII && $0.isHexDigit }) { return s }
        // Send QR URLs only to the fixed official parser, never navigate to the scanned host.
        // The session enables handoff only after the API confirms a washer device.
        guard let u = URLComponents(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), let host = u.host, !host.isEmpty, u.user == nil, u.password == nil, u.port == nil || (u.scheme == "https" && u.port == 443) || (u.scheme == "http" && u.port == 80) else {
            throw LaundryError(message: "请扫描洗衣机的完整二维码。")
        }
        let decoded = s.removingPercentEncoding ?? s
        let credentialPattern = "(?i)[?&#](?:access_?token|authorization|captcha|mobile|phone|ticket|auth_code|token)="
        guard decoded.range(of: credentialPattern, options: .regularExpression) == nil else { throw LaundryError(message: "这像是账号或登录链接，请扫描洗衣机二维码。") }
        return s
    }
    static func alipayMiniProgramURL(qrCode: String? = nil) throws -> URL {
        var link = URLComponents(string: "alipays://platformapi/startapp")!
        var items = [URLQueryItem(name: "appId", value: alipayAppID), URLQueryItem(name: "page", value: alipayHomePage)]
        if let qrCode {
            let original = try handoffQRCode(qrCode)
            var nested = URLComponents()
            nested.queryItems = [URLQueryItem(name: "qrcode", value: original)]
            let query = nested.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            items.append(URLQueryItem(name: "query", value: query))
        }
        link.queryItems = items
        return link.url!
    }
    static func rows(_ data: JSON) throws -> [JSON] {
        if case .array(let rows) = data { return rows }
        for key in ["list", "orders", "content", "records"] { if case .array(let rows) = data[key] { return rows } }
        throw LaundryError(message: "订单列表格式有变化，未把异常响应当成空订单。")
    }
    static func money(_ value: JSON) -> String {
        guard let cents = Double(value.text) else { return "价格待确认" }
        return String(format: "¥%.2f", cents / 100)
    }
    static func status(_ raw: JSON) -> String {
        if !raw["statusName"].text.isEmpty { return raw["statusName"].text }
        return ["10": "已预约（待支付）", "20": "已支付", "21": "启动中", "22": "自洁启动中", "24": "正在投放洗衣液", "29": "退单保护", "30": "自洁中", "35": "自洁完成", "40": "运行中", "50": "订单完成", "51": "超时未支付", "52": "启动失败", "53": "订单已取消", "54": "超时未启动", "60": "故障中", "61": "故障中"][raw["status"].text] ?? "状态 \(raw["status"].text)"
    }
}
