import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(_ bytes: Data = Data()) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var key = ""; @State private var token = ""; @State private var showShops = false
    @State private var exporting = false; @State private var importing = false; @State private var document = ConfigDocument()
    @State private var clearing = false; @State private var arming = false; @State private var resuming = false
    var body: some View {
        NavigationStack {
            Form {
                Section("运行模式") {
                    Toggle("连接 HTTPS 后端", isOn: $store.data.useBackend)
                    Text(store.data.useBackend ? "真实数据查询和服务端任务需要持续在线的后端。" : "当前为离线模拟，所有商品和支付状态均为测试数据。").font(.footnote).foregroundStyle(.secondary)
                    if store.data.useBackend {
                        TextField("https://你的后端域名", text: $store.data.backendURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("后端配对密钥", text: $key).textContentType(.password)
                        Button("保存密钥并验证连接") { store.perform { if !key.isEmpty { try Keychain.set("backendKey", key); key = "" }; try await store.connect() } }
                        if let s = store.status { LabeledContent("后端模式", value: s.mode == "mock" ? "模拟" : "真实查询"); LabeledContent("瑞幸授权", value: s.hasToken ? "已保存" : "尚未授权") }
                        Button("将本机配置同步到后端") { store.perform { try await store.sync(); store.message = "配置已同步" } }
                        Button("从后端恢复配置") { store.perform { try await store.loadServer(); store.message = "已载入后端配置" } }
                    }
                }
                Section("瑞幸账号授权") {
                    Link("打开瑞幸官方授权平台", destination: URL(string: "https://open.lkcoffee.com/mcp")!)
                    Text("登录、创建或撤销令牌均在官方网页完成。本 App 不收集瑞幸密码，不调用网页内部登录接口。").font(.footnote).foregroundStyle(.secondary)
                    Text("请在手机上打开官方平台，获取 Token 后回到这里粘贴。验证通过后会经 HTTPS 加密保存到你配对的后端。").font(.footnote).foregroundStyle(.secondary)
                    if store.data.useBackend {
                        SecureField("在手机粘贴官方 MCP Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        Button("验证并加密保存到后端") { store.perform { struct Body: Encodable { let token: String }; struct Result: Decodable { let verified: Bool }; let _: Result = try await store.api.send("POST", "/v1/token", Body(token: token)); token = ""; try await store.connect() } }.disabled(token.isEmpty)
                        Button("删除后端令牌并停止下单", role: .destructive) { store.perform { struct Result: Decodable { let revokedLocally: Bool }; let _: Result = try await store.api.request("DELETE", "/v1/token"); store.data.configuration.realOrdersEnabled = false; store.data.configuration.emergencyStop = true; try await store.connect() } }
                    }
                }
                Section("常用门店") {
                    Button { showShops = true } label: { LabeledContent("选择门店", value: store.data.configuration.shop?.name ?? "未选择") }
                    if let s = store.data.configuration.shop { Text(s.address).font(.footnote); Text(s.hours).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("消费限制 · 以分保存") {
                    CentField(title: "单杯最高", cents: $store.data.configuration.limits.cup)
                    CentField(title: "每日最高", cents: $store.data.configuration.limits.daily)
                    Stepper("每日最多 \(store.data.configuration.limits.dailyCount) 单", value: $store.data.configuration.limits.dailyCount, in: 1...20)
                    CentField(title: "每周最高", cents: $store.data.configuration.limits.weekly)
                    CentField(title: "每月最高", cents: $store.data.configuration.limits.monthly)
                    Text("默认每日一单。待付款与结果不明订单也占用预算。真实金额只采用官方服务端预览。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("付款方式") {
                    LabeledContent("主要入口", value: "瑞幸官方 App")
                    Text("真实订单详情提供官方 App 打开入口。请在官方订单中选择可用的微信、支付宝或银行卡等方式，并由对应渠道确认付款；具体可用方式以官方页面为准。").font(.footnote).foregroundStyle(.secondary)
                    Text("备用方式为另一块屏幕展示微信付款二维码。当前扫码类型不支持在同一部手机相册识别，也没有已验证的直接钱包收银台入口。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("真实下单授权") {
                    LabeledContent("当前状态", value: store.data.configuration.realOrdersEnabled ? "已授权" : "关闭")
                    Button("授权在预算内真实下单") { arming = true }.disabled(store.status?.liveOrdersAvailable != true)
                    LabeledContent("紧急停止", value: store.data.configuration.emergencyStop ? "已开启" : "已解除")
                    Button("恢复已授权的服务端任务调度") { resuming = true }.disabled(!store.data.useBackend)
                    Button("立即停止并同步到服务端", role: .destructive) { store.perform { try await store.stop() } }
                    Text("真实接口合同与付款流程未验收时，服务端锁定真实下单。离线更改不会影响服务端，停止任务请点击同步停止并确认成功。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("通知") {
                    Button("请求本机通知权限") { store.perform { let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]); store.message = ok ? "权限已授予；当前只实现站内通知箱，尚无远程推送" : "未授予通知权限，可在系统设置中修改" } }
                    Text("当前通知保存在服务端，打开 App 后查看。App 关闭时不能保证付款提醒；APNs 需独立证书与配置，尚未接入。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("数据与诊断") {
                    Button("导出咖啡池与配置") { do { document = ConfigDocument(try store.backup()); exporting = true } catch { store.message = error.localizedDescription } }
                    Button("从 JSON 备份恢复") { importing = true }
                    Text("备份不含 Token 或配对密钥。恢复后真实下单关闭，紧急停止开启。覆盖更新请保持签名身份和有效 Bundle ID 不变。").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("调试与操作记录") { AuditView() }
                    Button("清除本机数据", role: .destructive) { clearing = true }
                    Text("本机清除不删除服务端数据，也不撤销官方授权；先停止服务端任务。").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Text("Luckin Random · 瑞幸随机咖啡").font(.headline); Text("非瑞幸官方 App · 0.1.1").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("设置").sheet(isPresented: $showShops) { NavigationStack { ShopPicker().environmentObject(store) } }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "LuckinRandom-配置备份") { result in if case .failure(let e) = result { store.message = e.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }; try store.restore(Data(contentsOf: url)); store.message = "配置已恢复，真实下单保持关闭" } catch { store.message = error.localizedDescription }
                }
                .confirmationDialog("清除本机咖啡池与历史？请先导出备份并停止服务端任务。", isPresented: $clearing, titleVisibility: .visible) { Button("清除本机数据", role: .destructive) { do { try store.clear() } catch { store.message = error.localizedDescription } } }
                .confirmationDialog("授权此后主动触发及已授权任务，在已设定消费限制内创建真实订单？付款仍由你确认。", isPresented: $arming, titleVisibility: .visible) { Button("明确授权真实下单") { store.perform { try await store.authorize(realOrders: true, renewLimits: true) } } }
                .confirmationDialog("恢复已授权任务的服务端调度？保留现有真实下单授权与限额。", isPresented: $resuming, titleVisibility: .visible) { Button("恢复任务调度") { store.perform { try await store.authorize(realOrders: store.data.configuration.realOrdersEnabled) } } }
        }
    }
}
struct CentField: View {
    let title: String; @Binding var cents: Int
    var body: some View { HStack { Text(title); Spacer(); TextField("金额（元）", value: Binding(get: { Double(cents)/100 }, set: { if $0.isFinite { cents = Int((min(max($0,0),1000000)*100).rounded()) } }), format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 90); Text("元").foregroundStyle(.secondary) } }
}
struct ShopPicker: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    @State private var query = ""; @State private var longitude = ""; @State private var latitude = ""
    @State private var shops: [Shop] = []; @State private var fetching = false
    var body: some View {
        List {
            Section("搜索常用门店") {
                TextField("城市、商圈或门店名称", text: $query)
                if store.data.useBackend { TextField("经度（GCJ-02）", text: $longitude).keyboardType(.numbersAndPunctuation); TextField("纬度（GCJ-02）", text: $latitude).keyboardType(.numbersAndPunctuation); Text("请输入准确坐标。不会使用 IP 粗定位推断距离。").font(.footnote).foregroundStyle(.secondary) }
                Button("查找门店") { search() }.disabled(fetching)
            }
            if fetching { ProgressView("查询门店") }
            ForEach(shops) { s in Button { store.data.configuration.shop = s; dismiss() } label: { VStack(alignment: .leading, spacing: 6) { Text(s.name).font(.headline); Text(s.address).font(.subheadline); Text(s.hours).font(.caption) }.foregroundStyle(.primary).padding(.vertical, 4) } }
        }.navigationTitle("选择门店").toolbar { Button("取消") { dismiss() } }.task { if !store.data.useBackend { shops = [MockCatalog.shop] } }
    }
    func search() { guard !store.data.useBackend || (Double(longitude) != nil && Double(latitude) != nil) else { store.message = "请填写有效的门店搜索经纬度"; return }; fetching = true; store.perform { defer { fetching = false }; shops = try await store.shops(query, longitude: Double(longitude) ?? 116.4, latitude: Double(latitude) ?? 39.9) } }
}
struct AuditView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            if let pending = store.data.pendingIntent { Section("待确认请求") { Text(pending).font(.caption).textSelection(.enabled); Text("只读恢复前禁止再次创建订单。"); Button("查询后端恢复状态") { store.perform { try await store.recover() } } } }
            ForEach(store.events) { e in VStack(alignment: .leading, spacing: 4) { Text(e.state).font(.headline); Text(e.detail); Text(e.at).font(.caption).foregroundStyle(.secondary) } }
            if store.events.isEmpty { Text("连接后端后可读取操作状态记录。不会显示认证令牌。") }
        }.navigationTitle("调试日志").task { if store.data.useBackend { store.perform { store.events = try await store.api.request("GET", "/v1/events") } } }
    }
}
