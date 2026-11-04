import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        NavigationStack {
            List {
                Section("统计 · 已支付订单") {
                    LabeledContent("真实累计实付", value: money(store.data.orders.filter { $0.paid && $0.mode == "live" }.reduce(0) { $0 + ($1.quote?.payableCents ?? 0) }))
                    LabeledContent("真实累计优惠", value: money(store.data.orders.filter { $0.paid && $0.mode == "live" }.reduce(0) { $0 + max(0, ($1.quote?.originalCents ?? 0) - ($1.quote?.payableCents ?? 0)) }))
                    LabeledContent("模拟已支付订单", value: "\(store.data.orders.filter { $0.paid && $0.mode == "mock" }.count) 单")
                    Text("模拟记录以“模拟”标示，不能作为真实消费凭据。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("订单记录") {
                    if store.data.orders.isEmpty { ContentUnavailableView("还没有订单", systemImage: "receipt", description: Text("先添加候选饮品，再试一次随机预览。")) }
                    ForEach(store.data.orders) { o in
                        NavigationLink(value: o.id) { VStack(alignment: .leading, spacing: 6) { Text(o.title).font(.headline); Text("\(o.mode == "mock" ? "模拟 · " : "")\(o.stateName) · \(money(o.quote?.payableCents ?? 0))").font(.subheadline).foregroundStyle(.secondary); Text(o.createdAt).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                Section("抽取频率") { ForEach(Array(Dictionary(grouping: store.data.draws, by: \.name).keys.sorted()), id: \.self) { name in LabeledContent(name, value: "\(store.data.draws.filter { $0.name == name }.count) 次") } }
                Section("抽取记录") { ForEach(store.data.draws.prefix(100)) { d in VStack(alignment: .leading) { Text(d.name); Text(d.at).font(.caption).foregroundStyle(.secondary) } } }
                if !store.notices.isEmpty { Section("服务端通知箱") { ForEach(store.notices) { n in VStack(alignment: .leading, spacing: 4) { Text(n.message); Text(n.at).font(.caption).foregroundStyle(.secondary) } } } }
            }.navigationTitle("历史订单").navigationDestination(for: String.self) { OrderView(orderID: $0) }
                .refreshable { do { try await store.refreshHistory() } catch { store.message = error.localizedDescription } }
                .toolbar { Button("刷新", systemImage: "arrow.clockwise") { store.perform { try await store.refreshHistory() } } }
        }
    }
}
struct OrderView: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    let orderID: String
    @State private var working = false
    var order: CoffeeOrder? { store.data.orders.first { $0.id == orderID } }
    var body: some View {
        Group {
            if let o = order {
                List {
                    Section {
                        Label(o.stateName, systemImage: o.paid ? "checkmark.seal.fill" : "receipt").font(.title2.bold()).foregroundStyle(CoffeeTheme.blue)
                        if o.mode == "mock" { Text("模拟订单，不会产生消费。下方模拟支付用于测试状态变化。").font(.footnote) }
                        Text(o.title).font(.headline)
                        Text(o.candidate?.summary ?? "").foregroundStyle(.secondary)
                        if let q = o.quote { Text(q.shop.name); Text(q.shop.address).font(.footnote); LabeledContent("原价", value: money(q.originalCents)); LabeledContent("官方匹配优惠", value: money(max(0,q.originalCents-q.payableCents))); LabeledContent("应付金额", value: money(q.payableCents)) }
                        LabeledContent("下单时间", value: o.createdAt)
                        if let id = o.officialOrderId { Text("订单号 \(id)").font(.caption).textSelection(.enabled) }
                    }
                    if let reason = o.reason { Section("处理结果") { Text(reason).foregroundStyle(.orange) } }
                    if o.state == "awaitingPayment", o.mode == "live" {
                        Section("官方付款二维码") {
                            if let value = o.paymentQRURL, let url = URL(string: value), url.scheme == "https" {
                                AsyncImage(url: url) { image in image.resizable().interpolation(.none).scaledToFit() } placeholder: { ProgressView("加载官方二维码") }.frame(maxWidth: .infinity, minHeight: 220).accessibilityLabel("官方付款二维码，不是取餐码")
                                Link("打开官方付款二维码页面", destination: url)
                                ShareLink("在另一块屏幕展示付款二维码", item: url)
                                Text("可在另一块屏幕展示后，用手机微信扫码付款。同机相册识码与直接跳转尚未验证；不会构造支付宝或微信支付参数。付款验证由支付渠道完成。").font(.footnote)
                            } else { Text("官方未返回可验证的付款二维码，请在瑞幸官方渠道核对订单。暂不能保证同机付款路径。") }
                        }
                    }
                    if o.paid {
                        Section("取餐信息") { if let code = o.pickupCode { Text(code).font(.largeTitle.monospaced().bold()).textSelection(.enabled) } else { Text("官方取餐号尚未返回，请稍后刷新。") }; Text("仅显示官方取餐号。当前没有经验证的取餐二维码数据。").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section {
                        if store.data.useBackend { Button("查询官方最新状态") { act { try await store.refresh(o) } } }
                        if o.state == "awaitingPayment" { Button("取消未支付订单", role: .destructive) { act { try await store.cancel(o) } } }
                        if o.mode == "mock", o.state == "awaitingPayment" { Button("模拟支付成功") { act { try await store.simulate(o, state: "paid") } }; Button("模拟支付失败") { act { try await store.simulate(o, state: "failed") } } }
                        if o.mode == "mock", o.state == "paid" { Button("模拟出餐并获取测试取餐号") { act { try await store.simulate(o, state: "ready") } } }
                        if o.state == "previewed" { Text("这是只读预览，没有创建订单。回首页可重新抽取并按最新价格处理。") }
                    }.disabled(working)
                    if !o.attempts.isEmpty { Section("候选校验记录") { ForEach(Array(o.attempts.enumerated()), id: \.offset) { _, a in Text(a.reason).font(.footnote) } } }
                }
            } else { ContentUnavailableView("找不到订单", systemImage: "receipt") }
        }.navigationTitle("订单详情").navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { dismiss() } }
    }
    func act(_ operation: @escaping () async throws -> Void) { working = true; store.perform { defer { working = false }; try await operation() } }
}
