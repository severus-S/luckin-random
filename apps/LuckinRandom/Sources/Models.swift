import Foundation

struct DrinkOption: Codable, Identifiable, Hashable { var id: Int; var name: String; var selected: Bool; var available: Bool }
struct DrinkAttribute: Codable, Identifiable, Hashable { var id: Int; var name: String; var options: [DrinkOption] }
struct Product: Codable, Identifiable, Hashable {
    var id: String; var name: String; var sku: String; var image: String?
    var category: String; var attributes: [DrinkAttribute]; var initialCents: Int; var estimateCents: Int
}
struct Shop: Codable, Identifiable, Hashable {
    var id: String; var name: String; var address: String; var longitude: Double; var latitude: Double; var hours: String
}
struct Preference: Codable, Hashable { var group: Int; var option: Int; var label: String }
struct Candidate: Codable, Identifiable, Hashable {
    var id = UUID().uuidString; var productId: String; var name: String; var sku: String
    var preferences: [Preference]; var note = ""; var weight = 1.0; var enabled = true
    var summary: String { preferences.map(\.label).joined(separator: " · ") }
}
struct CoffeePool: Codable, Identifiable, Hashable {
    var id = UUID().uuidString; var name = "我的咖啡池"; var candidates: [Candidate] = []
    var weighted = false; var avoidRepeat = true
}
struct Limits: Codable, Hashable { var cup = 2000; var daily = 2000; var weekly = 10000; var monthly = 30000; var dailyCount = 1 }
struct Configuration: Codable, Equatable {
    var schemaVersion = 1; var pools: [CoffeePool]; var selectedPoolId: String; var shop: Shop?
    var limits = Limits(); var realOrdersEnabled = false; var emergencyStop = true; var paymentPreference = "alipay"
    static func fresh() -> Configuration { let p = CoffeePool(); return Configuration(pools: [p], selectedPoolId: p.id) }
    func validate() throws {
        guard schemaVersion == 1, !pools.isEmpty, pools.count <= 30,
              pools.contains(where: { $0.id == selectedPoolId }), Set(pools.map(\.id)).count == pools.count,
              (1...20).contains(limits.dailyCount), limits.cup > 0,
              limits.daily >= 0, limits.weekly >= 0, limits.monthly >= 0 else { throw AppFailure("配置版本或消费限制无效") }
        for p in pools {
            guard !p.name.isEmpty, p.candidates.count <= 200, Set(p.candidates.map(\.id)).count == p.candidates.count,
                  p.candidates.allSatisfy({ !$0.productId.isEmpty && !$0.sku.isEmpty && $0.weight.isFinite && $0.weight > 0 && $0.weight <= 10000 }) else { throw AppFailure("咖啡池或饮品权重无效") }
        }
    }
}
struct Quote: Codable, Hashable {
    var product: Product; var shop: Shop; var payableCents: Int; var originalCents: Int; var coupons: [String]; var at: String
}
struct Attempt: Codable, Hashable { var candidateId: String; var reason: String }
struct CoffeeOrder: Codable, Identifiable, Hashable {
    var id: String; var state: String; var createdAt: String; var mode: String; var poolId: String
    var candidate: Candidate?; var quote: Quote?; var officialOrderId: String?; var paymentQRURL: String?
    var pickupCode: String?; var reason: String?; var attempts: [Attempt] = []
    var title: String { candidate?.name ?? "随机点单" }
    var stateName: String { ["validating":"正在校验", "previewed":"预览完成", "creating":"正在创建", "awaitingPayment":"待付款", "paid":"已付款", "preparing":"制作中", "ready":"待取餐", "completed":"已完成", "cancelled":"已取消", "unknown":"结果不明 · 请核对", "failed":"未完成"][state] ?? "未知状态" }
    var paid: Bool { ["paid", "preparing", "ready", "completed"].contains(state) }
}
struct Draw: Codable, Identifiable { var id = UUID().uuidString; var at: String; var candidateId: String; var name: String; var poolId: String }
struct AutoJob: Codable, Identifiable {
    var id = UUID().uuidString; var enabled = false; var authorized = false; var poolId: String; var shop: Shop
    var hour = 9; var minute = 0; var weekdays = [1,2,3,4,5]; var timezone = "Asia/Shanghai"; var maxCents = 2000
}
struct BackendStatus: Codable { var mode: String; var liveOrdersAvailable: Bool; var hasToken: Bool; var schemaVersion: Int }
struct InboxNotice: Codable, Identifiable { var id: Int; var at: String; var message: String; var read: Int }
struct JobRun: Codable, Identifiable { var jobId: String; var slot: String; var intentId: String; var id: String { jobId + slot } }
struct AuditEvent: Codable, Identifiable { var seq: Int; var intentId: String; var at: String; var state: String; var detail: String; var id: Int { seq } }
struct LocalData: Codable {
    var version = 1; var configuration: Configuration; var draws: [Draw] = []; var orders: [CoffeeOrder] = []
    var pendingIntent: String?; var pendingBackend: String?; var useBackend = false; var backendURL = ""
}
struct AppFailure: LocalizedError { var message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
func money(_ cents: Int) -> String { (Double(cents) / 100).formatted(.currency(code: "CNY")) }
func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

enum RandomPicker {
    static func pick(_ values: [Candidate], weighted: Bool, previous: String?, avoid: Bool, unit: Double = Double.random(in: 0..<1)) throws -> Candidate {
        var items = values.filter(\.enabled)
        if avoid && items.count > 1 { items.removeAll { $0.id == previous } }
        guard !items.isEmpty else { throw AppFailure("请先添加并启用候选饮品") }
        let weights = items.map { weighted ? $0.weight : 1 }
        guard weights.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10000 }) else { throw AppFailure("权重无效") }
        var ticket = unit * weights.reduce(0, +)
        for (item, weight) in zip(items, weights) { ticket -= weight; if ticket < 0 { return item } }
        return items[items.count - 1]
    }
}
enum MockCatalog {
    static let shop = Shop(id: "900001", name: "模拟门店 · 不产生消费", address: "测试数据，非真实门店", longitude: 116.4, latitude: 39.9, hours: "00:00–24:00")
    static let products: [Product] = ["模拟椰香拿铁", "模拟醇厚拿铁", "模拟果香美式"].enumerated().map { i, name in
        Product(id: String(900101 + i), name: name, sku: "MOCK-\(i)-cold", category: i == 2 ? "美式" : "拿铁", attributes: [DrinkAttribute(id: 1, name: "温度", options: [DrinkOption(id: 11, name: "冰", selected: true, available: true), DrinkOption(id: 12, name: "热", selected: false, available: true)]), DrinkAttribute(id: 2, name: "糖度", options: [DrinkOption(id: 21, name: "标准", selected: true, available: true), DrinkOption(id: 22, name: "少糖", selected: false, available: true)])], initialCents: 1800, estimateCents: 990)
    }
}
