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
    @Published var device: JSON = .null
    @Published var scan: JSON = .null
    @Published var running: [JSON] = []
    @Published var history: [JSON] = []
    @Published var ordersLoaded = false
    @Published var ordersError = ""
    @Published var order: JSON = .null
    @Published var paymentMethods: [JSON] = []
    @Published var payURL: URL?
    @Published var historyPage = 1
    private let api = LaundryAPI()
    private var generation = 0
    var loggedIn: Bool { !token.isEmpty }
    var programs: [JSON] { device["deviceWashModel"].list }
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
        guard !access.isEmpty else { throw LaundryError(message: "登录响应未返回会话，未保存登录状态。") }
        // Confirm the same account can access the washer service before claiming login succeeded.
        let rows = try LaundryProtocol.rows(await api.call("orders/running", token: access))
        try CredentialStore.save(access)
        token = access
        running = rows
        ordersLoaded = true
        note = "已登录"
    }
    func login(mobile: String, code: String) async throws {
        guard mobile.count == 11, mobile.hasPrefix("1"), mobile.allSatisfy({ $0.isNumber && $0.isASCII }), !code.isEmpty, code.count <= 12 else { throw LaundryError(message: "请检查手机号和验证码。") }
        let result = try await api.call("login", method: "POST", body: .object(["mobile": .string(mobile), "captcha": .string(code)]))
        try await acceptAccessToken(result.firstText("token", "accessToken"))
    }
    func logout() {
        guard !busy else { return }
        generation += 1
        CredentialStore.clear()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        token = ""
        device = .null; scan = .null; order = .null
        running = []; history = []; paymentMethods = []
        payURL = nil; ordersLoaded = false; ordersError = ""; note = ""
    }
    func identify(_ input: String, isDeviceID: Bool = false) async throws {
        let access = token
        guard !access.isEmpty else { throw LaundryError(message: "请先登录。") }
        device = .null; scan = .null; order = .null; note = ""
        var identifier = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: JSON = .null
        if !isDeviceID {
            result = try await api.call("devices/scanWasherCode", method: "POST", body: .object(["qrCode": .string(try LaundryProtocol.qrCode(input))]), token: access)
            scan = result
            if !result["orderId"].text.isEmpty, result["createOrderEnabled"] == .bool(false) {
                try await loadOrder(result["orderId"].text)
                device = .null
                return
            }
            guard result["createOrderEnabled"].flag else { throw LaundryError(message: "该设备当前不可下单，请查看机器状态或使用官方 U净。") }
            identifier = result["deviceId"].text
        }
        identifier = try LaundryProtocol.identifier(identifier)
        let info = try await api.call("app/washer/devices/program/info", query: ["deviceId": identifier], token: access)
        guard !info["deviceId"].text.isEmpty, case .array = info["deviceWashModel"] else { throw LaundryError(message: "设备程序响应不完整，未允许下单。") }
        device = info
        order = .null
        if LaundryProtocol.bluetoothRequired(info) || LaundryProtocol.bluetoothRequired(result) { note = "识别到蓝牙机型。本版暂未实现其专用启动协议，请使用官方 U净完成本次洗衣。" }
        else { note = "已读取设备与程序" }
    }
    func create(program: JSON, extras: [String: JSON]) async throws {
        guard !LaundryProtocol.bluetoothRequired(scan) else { throw LaundryError(message: "此设备需要蓝牙控制，本版暂不能启动，已阻止创建洗衣订单。") }
        let body = try LaundryProtocol.orderBody(device: device, program: program, extras: extras)
        let result = try await api.call("orders/create", method: "POST", body: body, token: token)
        guard !result["orderId"].text.isEmpty else { throw LaundryError(message: "未获得订单号。请先刷新订单列表确认结果，再决定是否重试。") }
        // Keep the created order ID even if the subsequent detail request fails. Never retry create automatically.
        order = .object(["orderId": result["orderId"], "statusName": .string("已创建，请刷新详情")])
        device = .null
        try await loadOrder(result["orderId"].text)
        note = "订单已创建，请核对金额后支付。"
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
        paymentMethods = []
    }
    func loadPaymentMethods() async throws {
        let id = try LaundryProtocol.identifier(order["orderId"].text)
        let result = try await api.call("payment/methods", query: ["orderId": id, "serviceSubjectId": order["serviceSubjectId"].text, "deviceId": order["deviceId"].text, "include": "alipay"], token: token)
        guard case .array(let channels) = result["channels"] else { throw LaundryError(message: "支付渠道响应不完整。") }
        // Only explicitly advertised H5 channels can run without the merchant's registered iOS SDK identity.
        paymentMethods = channels.filter { channel in
            ["alipayF2F", "alipay"].contains(channel["channel"].text) && (channel["channel"].text == "alipayF2F" || channel["branchType"].integer == 1) && !channel["needOAuth"].flag && !channel["needUpgrade"].flag
        }
        note = paymentMethods.isEmpty ? "该订单未提供本版可用的网页支付渠道。官方 App SDK 支付尚未接入，请使用官方 U净处理。" : "请先核对订单金额；点击支付将创建支付请求。"
    }
    func pay(channel: JSON, useBalance: Bool) async throws {
        let id = try LaundryProtocol.identifier(order["orderId"].text)
        let result = try await api.call("payment/arguments", query: ["orderId": id, "channel": channel["channel"].text, "branchType": channel["branchType"].text.isEmpty ? "0" : channel["branchType"].text, "isUseRedPacket": useBalance ? "true" : "false", "couponId": "", "redPacketId": "0", "payVersion": "1"], token: token)
        if result["skipPay"].flag || result["jumpToQuery"].flag {
            note = "服务端已受理支付，请刷新订单确认状态。"
            try await loadOrder(id)
            return
        }
        let value = result["payInfo"].firstText("url", "payUrl", "mweb_url")
        let url = LaundryProtocol.paymentURL(value.isEmpty ? result["payInfo"].text : value)
        guard let url else { throw LaundryError(message: "服务端返回了需官方支付 SDK 处理的参数，本版无法唤起。未将其标记为支付成功，请到官方 U净查看此订单。") }
        payURL = url
        note = "请在支付页完成操作，返回后刷新订单。"
    }
    func control(_ command: String) async throws {
        guard ["start", "stop", "continue", "selfClean"].contains(command) else { return }
        guard !LaundryProtocol.bluetoothRequired(order) else { throw LaundryError(message: "此机型需专用蓝牙控制，请使用官方 U净。") }
        guard LaundryProtocol.networkControlSupported(order) else { throw LaundryError(message: "尚未确认设备的控制协议，未发送启动指令。") }
        let id = try LaundryProtocol.identifier(order["orderId"].text)
        _ = try await api.call("orders/\(id)/control/\(command)", token: token)
        note = "指令已提交，请核对机器实际状态并刷新订单。"
        try await loadOrder(id)
    }
    func cancelOrder() async throws {
        let id = try LaundryProtocol.identifier(order["orderId"].text)
        _ = try await api.call("orders/\(id)/cancel", method: "POST", body: .object(["orderId": order["orderId"]]), token: token)
        try await loadOrder(id)
        note = "取消请求已受理，请核对订单与退款状态。"
    }
}
