import SwiftUI
import Security
import WebKit

enum CredentialStore {
    private static let service = "com.sjx13.ios.uwash.session"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "access-token"] }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw LaundryError(message: "无法安全保存登录，请重试。") }
        } else if status != errSecSuccess { throw LaundryError(message: "无法更新安全登录资料。") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor final class LaundrySession: ObservableObject {
    @Published private(set) var token = CredentialStore.read()
    @Published var busy = false
    @Published var error: String?
    @Published var note = ""
    @Published private(set) var device: JSON = .null
    @Published private(set) var deviceQRCode = ""
    @Published var running: [JSON] = []
    @Published var history: [JSON] = []
    @Published var ordersLoaded = false
    @Published var ordersError = ""
    @Published var order: JSON = .null
    @Published var historyPage = 1
    private let api = LaundryAPI()
    private var generation = 0
    var loggedIn: Bool { !token.isEmpty }
    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        let current = generation
        Task {
            defer { if generation == current { busy = false } }
            do { try await action() }
            catch is CancellationError {}
            catch { if generation == current { self.error = error.localizedDescription } }
        }
    }
    func acceptAccessToken(_ access: String) async throws {
        guard !access.isEmpty, access != "null", access != "undefined" else { throw LaundryError(message: "尚未读取到登录结果，请先在官方网页完成登录。") }
        // Confirm the same account can access the washer service before claiming login succeeded.
        let rows = try LaundryProtocol.rows(await api.call("orders/running", token: access))
        try CredentialStore.save(access)
        token = access
        device = .null; deviceQRCode = ""; order = .null; history = []; historyPage = 1
        running = rows
        ordersLoaded = false; ordersError = ""
        note = "网页登录已验证，可以扫码识别洗衣机。"
    }
    func logout() {
        guard !busy else { return }
        generation += 1
        CredentialStore.clear()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        token = ""
        device = .null; deviceQRCode = ""
        order = .null
        running = []; history = []
        ordersLoaded = false; ordersError = ""; note = ""
    }
    func clearDevice() { device = .null; deviceQRCode = ""; note = "" }
    func identify(_ raw: String) async throws {
        clearDevice(); note = ""
        guard loggedIn else { throw LaundryError(message: "请先完成 U净网页登录。") }
        let qr = try LaundryProtocol.handoffQRCode(raw)
        let parsed = try await api.call("devices/scanWasherCode", method: "POST", body: .object(["qrCode": .string(qr)]), token: token)
        let id = try LaundryProtocol.identifier(parsed["deviceId"].text)
        let info = try await api.call("app/washer/devices/program/info", query: ["deviceId": id], token: token)
        device = try LaundryProtocol.washerDevice(info)
        deviceQRCode = qr
        note = "已识别洗衣机。点击下方按钮，在 U净支付宝小程序选择洗衣程序并核对付款。"
    }
    func openAlipay() throws {
        guard loggedIn, !device.fields.isEmpty, !deviceQRCode.isEmpty else { throw LaundryError(message: "请先登录并识别洗衣机。") }
        let url = try LaundryProtocol.alipayMiniProgramURL(qrCode: deviceQRCode)
        UIApplication.shared.open(url) { opened in
            if opened {
                self.note = "已尝试带入二维码。若小程序没有自动识别设备，请在小程序内再扫码一次；返回净洗后可刷新订单。"
            } else { self.error = "无法打开支付宝，请先安装支付宝后再试。" }
        }
    }
    func loadOrders(page: Int = 1) async throws {
        do {
            let a = try await api.call("orders/running", token: token)
            let b = try await api.call("orders/history", query: ["page": String(page), "size": "20"], token: token)
            let current = try LaundryProtocol.rows(a), older = try LaundryProtocol.rows(b)
            running = current; history = older; historyPage = page
            ordersLoaded = true; ordersError = ""
        } catch { ordersError = "订单读取失败，保留上次结果。"; throw error }
    }
    func loadOrder(_ id: String) async throws {
        let id = try LaundryProtocol.identifier(id)
        let detail = try await api.call("orders/\(id)/detail", query: ["additional": "price"], token: token)
        guard !detail["orderId"].text.isEmpty else { throw LaundryError(message: "未收到完整订单详情。") }
        order = detail
    }
}
