import SwiftUI
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    static let shared = AppStore()
    @Published var data: LocalData { didSet { persist() } }
    @Published var busy = false
    @Published var message: String?
    @Published var status: BackendStatus?
    @Published var jobs: [AutoJob] = []
    @Published var runs: [JobRun] = []
    @Published var notices: [InboxNotice] = []
    @Published var events: [AuditEvent] = []
    @Published var selectedTab = 0
    @Published var phase = ""
    @Published var lastOrder: CoffeeOrder?
    private var loading = false
    private let file: URL
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LuckinRandom", isDirectory: true)
        file = dir.appendingPathComponent("state-v1.json")
        var error: String?
        if FileManager.default.fileExists(atPath: file.path) {
            do { let saved = try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: file)); guard saved.version == 1 else { throw AppFailure("数据版本需要迁移") }; try saved.configuration.validate(); data = saved }
            catch { data = LocalData(configuration: .fresh()); error = "本地配置读取失败，原文件已保留。请通过备份恢复，避免覆盖原数据。"; loading = true }
        } else { data = LocalData(configuration: .fresh()) }
        message = error
    }
    var pool: CoffeePool { data.configuration.pools.first { $0.id == data.configuration.selectedPoolId } ?? data.configuration.pools[0] }
    var api: API { API(base: data.backendURL) }
    var mock: Bool { !data.useBackend || status?.mode == "mock" }
    func persist() {
        guard !loading else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = "本地保存失败，请导出配置备份后再操作" }
    }
    func replacePool(_ p: CoffeePool) { if let n = data.configuration.pools.firstIndex(where: { $0.id == p.id }) { data.configuration.pools[n] = p } }
    func addPool(_ name: String) { let p = CoffeePool(name: name.isEmpty ? "新咖啡池" : name); data.configuration.pools.append(p); data.configuration.selectedPoolId = p.id }
    func removePool(_ id: String) {
        guard data.configuration.pools.count > 1 else { return }
        data.configuration.pools.removeAll { $0.id == id }; if data.configuration.selectedPoolId == id { data.configuration.selectedPoolId = data.configuration.pools[0].id }
    }
    func add(_ product: Product) {
        let prefs = product.attributes.flatMap { a in a.options.filter(\.selected).map { Preference(group: a.id, option: $0.id, label: $0.name) } }
        var p = pool
        guard !p.candidates.contains(where: { $0.productId == product.id && $0.preferences == prefs }) else { message = "这款饮品和规格已在咖啡池中"; return }
        p.candidates.append(Candidate(productId: product.id, name: product.name, sku: product.sku, preferences: prefs)); replacePool(p)
    }
    func perform(_ work: @escaping () async throws -> Void) {
        Task { do { try await work() } catch { message = error.localizedDescription } }
    }
    func connect() async throws { let s: BackendStatus = try await api.request("GET", "/v1/status"); status = s; message = s.mode == "mock" ? "已连接模拟后端，不产生消费" : "已连接真实查询后端；真实下单仍需单独授权" }
    func sync() async throws {
        try data.configuration.validate()
        let result: Configuration = try await api.send("PUT", "/v1/config", data.configuration)
        data.configuration.realOrdersEnabled = result.realOrdersEnabled; data.configuration.emergencyStop = result.emergencyStop
    }
    func authorize(realOrders: Bool, renewLimits: Bool = false) async throws {
        try await sync()
        struct Authorization: Encodable { var confirmation = "AUTHORIZE_WITH_SAVED_LIMITS"; var enableRealOrders: Bool; var resumeTasks = true; var authorizeLimits: Bool }
        let c: Configuration = try await api.send("POST", "/v1/authorization", Authorization(enableRealOrders: realOrders, authorizeLimits: renewLimits))
        data.configuration.realOrdersEnabled = c.realOrdersEnabled; data.configuration.emergencyStop = c.emergencyStop
    }
    func loadServer() async throws { let c: Configuration = try await api.request("GET", "/v1/config"); try c.validate(); data.configuration = c }
    func products(_ query: String) async throws -> [Product] {
        if !data.useBackend { return MockCatalog.products.filter { query.isEmpty || $0.name.contains(query) } }
        try await sync(); return try await api.request("GET", "/v1/products?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
    func detail(_ id: String, preferences: [Preference] = []) async throws -> Product {
        if !data.useBackend {
            guard var p = MockCatalog.products.first(where: { $0.id == id }) else { throw AppFailure("模拟商品不存在") }
            for v in preferences { if let n = p.attributes.firstIndex(where: { $0.id == v.group }) { for i in p.attributes[n].options.indices { p.attributes[n].options[i].selected = p.attributes[n].options[i].id == v.option } } }
            return p
        }
        struct Body: Encodable { let id: String; let preferences: [Preference] }
        return try await api.send("POST", "/v1/product-detail", Body(id: id, preferences: preferences))
    }
    func shops(_ query: String, longitude: Double, latitude: Double) async throws -> [Shop] {
        if !data.useBackend { return [MockCatalog.shop] }
        return try await api.request("GET", "/v1/shops?longitude=\(longitude)&latitude=\(latitude)&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }
    func buy(previewOnly: Bool = false) async {
        guard !busy else { return }
        busy = true; phase = "校验候选与规格"; defer { busy = false; phase = "" }
        var sentID: String?
        do {
            if data.useBackend {
                if data.pendingIntent != nil { try await recover(); if data.pendingIntent != nil { throw AppFailure("上一次点单结果仍不明，已禁止再次创建。请查询历史并核对官方订单") } }
                try await sync()
                let id = UUID().uuidString; data.pendingIntent = id; data.pendingBackend = data.backendURL
                sentID = id
                phase = "获取官方优惠与预算校验"
                struct Body: Encodable { let id: String; let poolId: String; let previewOnly: Bool }
                // Keep the key on every network error; recovery only queries, never resends POST.
                let order: CoffeeOrder = try await api.send("POST", "/v1/orders", Body(id: id, poolId: pool.id, previewOnly: previewOnly))
                upsert(order); data.pendingIntent = nil; data.pendingBackend = nil; lastOrder = order
            } else { try localBuy(preview: previewOnly) }
        } catch {
            if let failure = error as? HTTPFailure, (400..<500).contains(failure.status), let sentID, data.pendingIntent == sentID {
                data.pendingIntent = nil; data.pendingBackend = nil
            }
            message = error.localizedDescription
        }
    }
    private func localBuy(preview: Bool) throws {
        guard let shop = data.configuration.shop else { throw AppFailure("请先在设置中选择模拟门店") }
        guard shop.id == MockCatalog.shop.id else { throw AppFailure("当前为离线模拟，请先选择模拟门店；真实门店请连接后端") }
        let p = pool, previous = data.orders.first { $0.poolId == p.id && $0.officialOrderId != nil }?.candidate?.id
        let candidate = try RandomPicker.pick(p.candidates, weighted: p.weighted, previous: previous, avoid: p.avoidRepeat)
        guard var product = MockCatalog.products.first(where: { $0.id == candidate.productId }) else { throw AppFailure("离线模拟只能选择模拟商品；真实商品需联网校验") }
        for pref in candidate.preferences {
            guard let n = product.attributes.firstIndex(where: { $0.id == pref.group }), product.attributes[n].options.contains(where: { $0.id == pref.option && $0.available }) else { throw AppFailure("保存的模拟规格已失效") }
            for j in product.attributes[n].options.indices { product.attributes[n].options[j].selected = product.attributes[n].options[j].id == pref.option }
        }
        let limits = data.configuration.limits, price = product.estimateCents
        guard price <= limits.cup else { throw AppFailure("模拟价格超过单杯上限") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let active = data.orders.filter { $0.mode == "mock" && !["failed","cancelled","previewed"].contains($0.state) }
        let date = ISO8601DateFormatter()
        let day = active.filter { date.date(from: $0.createdAt).map { calendar.isDate($0, inSameDayAs: Date()) } ?? false }
        let week = active.filter { date.date(from: $0.createdAt).map { calendar.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) } ?? false }
        let month = active.filter { date.date(from: $0.createdAt).map { calendar.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false }
        guard day.count < limits.dailyCount, day.reduce(0, { $0 + ($1.quote?.payableCents ?? 0) }) + price <= limits.daily,
              week.reduce(0, { $0 + ($1.quote?.payableCents ?? 0) }) + price <= limits.weekly,
              month.reduce(0, { $0 + ($1.quote?.payableCents ?? 0) }) + price <= limits.monthly else { throw AppFailure("达到模拟消费限制；可先取消未支付模拟订单") }
        let id = UUID().uuidString
        let q = Quote(product: product, shop: shop, payableCents: price, originalCents: product.initialCents, coupons: ["MOCK-COUPON"], at: timestamp())
        let order = CoffeeOrder(id: id, state: preview ? "previewed" : "awaitingPayment", createdAt: timestamp(), mode: "mock", poolId: p.id, candidate: candidate, quote: q, officialOrderId: preview ? nil : "MOCK-\(id)")
        upsert(order); lastOrder = order
    }
    func upsert(_ order: CoffeeOrder) {
        let existed = data.orders.contains { $0.id == order.id }
        if let n = data.orders.firstIndex(where: { $0.id == order.id }) { data.orders[n] = order } else { data.orders.insert(order, at: 0) }
        if !existed, let candidate = order.candidate {
            data.draws.insert(Draw(at: order.createdAt, candidateId: candidate.id, name: candidate.name, poolId: order.poolId), at: 0)
        }
    }
    func recover() async throws {
        if let pending = data.pendingIntent {
            guard data.pendingBackend == data.backendURL else { throw AppFailure("存在另一后端的待确认请求，请先恢复原地址核对") }
            let list: [CoffeeOrder] = try await api.request("GET", "/v1/orders")
            for i in list { upsert(i) }
            if list.contains(where: { $0.id == pending }) { data.pendingIntent = nil; data.pendingBackend = nil }
        }
    }
    func refreshHistory() async throws {
        guard data.useBackend else { return }
        try await recover()
        let orders: [CoffeeOrder] = try await api.request("GET", "/v1/orders")
        for order in orders { upsert(order) }
        notices = try await api.request("GET", "/v1/notifications")
    }
    func refresh(_ order: CoffeeOrder) async throws {
        guard data.useBackend else { return }
        let value: CoffeeOrder = try await api.request("POST", "/v1/orders/\(order.id)/refresh"); upsert(value)
    }
    func cancel(_ order: CoffeeOrder) async throws {
        if data.useBackend { let value: CoffeeOrder = try await api.request("POST", "/v1/orders/\(order.id)/cancel"); upsert(value) }
        else { guard order.mode == "mock", order.state == "awaitingPayment" else { throw AppFailure("仅可取消未付款订单") }; var i = order; i.state = "cancelled"; upsert(i) }
    }
    func simulate(_ order: CoffeeOrder, state: String) async throws {
        guard order.mode == "mock" else { return }
        if data.useBackend { struct Body: Encodable { var state: String }; let i: CoffeeOrder = try await api.send("POST", "/v1/orders/\(order.id)/simulate", Body(state: state)); upsert(i) }
        else { var i = order; i.state = state; i.pickupCode = state == "ready" ? "MOCK-A001" : nil; upsert(i) }
    }
    func refreshJobs() async throws { guard data.useBackend else { return }; jobs = try await api.request("GET", "/v1/jobs"); runs = try await api.request("GET", "/v1/job-runs") }
    func saveJob(_ j: AutoJob) async throws { try await sync(); let _: AutoJob = try await api.send("PUT", "/v1/jobs", j); try await refreshJobs() }
    func stop() async throws { data.configuration.emergencyStop = true; data.configuration.realOrdersEnabled = false; if data.useBackend { let c: Configuration = try await api.request("POST", "/v1/emergency-stop"); data.configuration = c } }
    func backup() throws -> Data { try JSONEncoder().encode(data.configuration) }
    func restore(_ bytes: Data) throws { var c = try JSONDecoder().decode(Configuration.self, from: bytes); try c.validate(); c.realOrdersEnabled = false; c.emergencyStop = true; loading = false; data.configuration = c }
    func clear() throws { guard data.pendingIntent == nil else { throw AppFailure("存在结果未确认的请求，请先核对后再清除") }; loading = false; data = LocalData(configuration: .fresh()); try Keychain.set("backendKey", ""); status = nil }
}
