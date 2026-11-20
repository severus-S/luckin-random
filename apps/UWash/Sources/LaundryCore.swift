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
            let code = value?["code"].text ?? "UNKNOWN"
            // Server text may contain credentials or reflected input. Keep diagnostics bounded and value-free.
            throw LaundryError(message: "服务端未完成请求（代码 \(code.prefix(20))）。请检查账号、设备状态后重试。")
        }
        guard value.fields.keys.contains("data") else { throw LaundryError(message: "服务端响应缺少数据，未更新本地状态。") }
        return value["data"]
    }
    static func request(path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil, token: String = "") throws -> URLRequest {
        guard !path.contains("://"), !path.contains(".."), !path.hasPrefix("/"), !path.contains("?"), !path.contains("#") else { throw LaundryError(message: "无效的接口地址。") }
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
    static func qrCode(_ text: String) throws -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...4096).contains(s.count), !s.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { throw LaundryError(message: "二维码内容无效。") }
        // Send the original code to the official parser. Never navigate to arbitrary scanned websites.
        return s
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
    static func bluetoothRequired(_ data: JSON) -> Bool {
        [1, 4, 5].contains(data["moduleType"].integer ?? -1) || data["needSyncBLE"].flag
    }
    static func networkControlSupported(_ data: JSON) -> Bool {
        [0, 2, 3, 6, 7].contains(data["moduleType"].integer ?? -1) && !data["needSyncBLE"].flag
    }
    static func orderBody(device: JSON, program: JSON, extras: [String: JSON]) throws -> JSON {
        guard !bluetoothRequired(device) else { throw LaundryError(message: "此机型需要专用蓝牙协议，本版暂不能启动，请使用官方 U净完成本次洗衣。") }
        guard networkControlSupported(device) else { throw LaundryError(message: "尚未确认此机型的控制协议，已阻止下单。") }
        guard device["type"].integer == 1 else { throw LaundryError(message: "本版只支持洗衣下单，烘干等设备请使用官方 U净。") }
        guard device["notification"]["usageLimit"].integer != 1 else { throw LaundryError(message: "门店当前限制下单，请查看门店通知。") }
        var fields: [String: JSON] = [:]
        for key in ["type", "deviceTypeId", "deviceId", "storeId"] {
            guard !device[key].text.isEmpty else { throw LaundryError(message: "设备资料不完整，请重新识别。") }
            fields[key] = device[key]
        }
        guard !program["workModelId"].text.isEmpty else { throw LaundryError(message: "请选择洗衣程序。") }
        fields["deviceWashModelId"] = program["workModelId"]
        let groups = program["additionDevices"]["washingPartnerFeature"].list + program["additionParams"].list
        let allowed = Set(groups.map { $0["key"].text }.filter { !$0.isEmpty })
        for (key, id) in extras {
            guard allowed.contains(key), groups.contains(where: { $0["key"].text == key && $0["options"].list.contains(where: { $0["id"] == id }) }) else { throw LaundryError(message: "附加项目已变化，请重新选择。") }
            fields[key] = id
        }
        for key in ["isForceDetergent", "isForceDisinfectant"] where device[key].flag {
            let requiredKey = key == "isForceDetergent" ? "wp_detergentGearId" : "wp_disinfectantGearId"
            guard fields[requiredKey] != nil else { throw LaundryError(message: "门店要求选择洗衣液或除菌液，请先完成附加项目。") }
        }
        return .object(fields)
    }
    static func status(_ raw: JSON) -> String {
        if !raw["statusName"].text.isEmpty { return raw["statusName"].text }
        return ["10": "已预约（待支付）", "20": "已支付", "21": "启动中", "22": "自洁启动中", "24": "正在投放洗衣液", "29": "退单保护", "30": "自洁中", "35": "自洁完成", "40": "运行中", "50": "订单完成", "51": "超时未支付", "52": "启动失败", "53": "订单已取消", "54": "超时未启动", "60": "故障中", "61": "故障中"][raw["status"].text] ?? "状态 \(raw["status"].text)"
    }
    static func paymentURL(_ value: String) -> URL? {
        guard let u = URL(string: value), u.user == nil, u.password == nil else { return nil }
        let host = u.host?.lowercased() ?? ""
        if u.scheme == "https", ["alipay.com", "alipayobjects.com", "tenpay.com", "weixin.qq.com", "zhinengxiyifang.cn", "ujing.online"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return u }
        if ["alipays", "alipay", "weixin"].contains(u.scheme?.lowercased() ?? "") { return u }
        return nil
    }
}
