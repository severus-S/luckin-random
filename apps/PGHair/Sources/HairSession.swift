import SwiftUI
import Security
import WebKit

enum HairCredentials {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sjx13.ios.pghair", kSecAttrAccount as String: "session"]
    static func read() -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = Data(token.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw HairError(message: "无法安全保存登录。") }
        } else if status != errSecSuccess { throw HairError(message: "无法更新安全登录。") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

final class HairAPI: NSObject, URLSessionTaskDelegate {
    private lazy var client = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func read(_ path: String, method: String = "POST", values: [String: String] = [:], token: String) async throws -> JSON {
        guard !token.isEmpty else { throw HairError(message: "请先登录胖乖生活。") }
        do {
            let (data, response) = try await client.data(for: HairPolicy.request(path, method: method, values: values, token: token))
            guard let response = response as? HTTPURLResponse else { throw HairError(message: "未收到有效网络响应。") }
            return try HairPolicy.unwrap(data, status: response.statusCode)
        } catch let error as HairError { throw error }
        catch { throw HairError(message: "网络请求失败，请检查网络后重试。") }
    }
}

@MainActor final class HairSession: ObservableObject {
    @Published var busy = false
    @Published var error: String?
    @Published private(set) var account: JSON = .null
    @Published private(set) var device: JSON = .null
    @Published private(set) var parameters: [String: String] = [:]
    @Published private(set) var orders: [JSON] = []
    @Published private(set) var page = 1
    @Published private(set) var canNext = false
    @Published private(set) var ordersLoaded = false
    @Published var note = ""
    private var token = HairCredentials.read()
    private let api = HairAPI()
    var hasCredential: Bool { !token.isEmpty }
    var verified: Bool { !account.fields.isEmpty }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await work() }
            catch let e as HairError { self.error = e.message }
            catch { self.error = "操作未完成，请重试。" }
        }
    }
    func accept(_ access: String) async throws {
        guard !access.isEmpty, access != "null", access != "undefined" else { throw HairError(message: "尚未读取到登录，请先在网页完成手机号登录。") }
        let info = try await api.read("user/info", method: "GET", token: access)
        guard !info["id"].text.isEmpty || !info["phone"].text.isEmpty else { throw HairError(message: "未收到有效账号资料，未确认登录。") }
        try HairCredentials.save(access)
        token = access; account = info; note = "登录已验证"
    }
    func refreshAccount() async throws {
        let info = try await api.read("user/info", method: "GET", token: token)
        guard !info["id"].text.isEmpty || !info["phone"].text.isEmpty else { throw HairError(message: "未收到有效账号资料。") }
        account = info
    }
    func identify(_ raw: String) async throws {
        parameters = [:]; device = .null; note = ""
        let params = try HairPolicy.scanParameters(raw)
        let result = try await api.read("goods/scan/v2", values: params, token: token)
        let type = result["type"].text, id = result["id"].text
        guard ["goods", "machine"].contains(type), !id.isEmpty else { throw HairError(message: "没有识别到有效的胖乖设备。") }
        let path = type == "goods" ? "goods/normal/details" : "machine/detail"
        let detail = try await api.read(path, values: [type == "goods" ? "goodsId" : "machineId": id], token: token)
        guard HairPolicy.isHairDevice(detail, type: type) else { throw HairError(message: "这个码未被确认是吹风机。精简版仅接入吹风机设备。") }
        device = detail; parameters = params
        note = "已识别吹风机。点击下方按钮，在官方支付宝小程序选择时长并核对付款。"
    }
    func refreshOrders(_ requested: Int = 1) async throws {
        let info = try await api.read("order/list", method: "GET", values: ["page": String(requested), "pageSize": "20"], token: token)
        let rows = try HairPolicy.orderRows(info)
        orders = rows.filter(HairPolicy.isHairOrder); page = requested; canNext = rows.count >= 20; ordersLoaded = true
        note = "本页显示已识别为吹风机的订单；分页按服务端全部订单计算。"
    }
    func openAlipay() throws {
        let link = try HairPolicy.miniProgramURL(parameters)
        UIApplication.shared.open(link) { opened in
            if !opened { self.error = "无法打开支付宝，请先安装支付宝后再试。" }
            else { self.note = "已打开官方支付宝小程序。实际下单、付款和设备启动以该页面及机器状态为准；返回后可刷新订单。" }
        }
    }
    func logout() {
        guard !busy else { return }
        token = ""; account = .null; device = .null; parameters = [:]; orders = []; ordersLoaded = false; note = ""
        HairCredentials.clear()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}
