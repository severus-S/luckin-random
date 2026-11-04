import SwiftUI

enum CoffeeTheme {
    static let blue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.65, blue: 1, alpha: 1) : UIColor(red: 0.05, green: 0.18, blue: 0.55, alpha: 1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}
struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            HomeView().tabItem { Label("首页", systemImage: "cup.and.saucer.fill") }.tag(0)
            PoolsView().tabItem { Label("咖啡池", systemImage: "square.stack.3d.up") }.tag(1)
            TasksView().tabItem { Label("自动任务", systemImage: "clock") }.tag(2)
            HistoryView().tabItem { Label("历史订单", systemImage: "receipt") }.tag(3)
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .tint(CoffeeTheme.blue)
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了") { store.message = nil } } message: { Text(store.message ?? "") }
        .sheet(item: $store.lastOrder) { order in NavigationStack { OrderView(orderID: order.id).environmentObject(store) } }
    }
}
struct ModeBanner: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Label(store.data.useBackend ? (store.status?.mode == "live" ? "真实查询 · 下单需单独授权" : "后端模式 · 请核对连接状态") : "离线模拟 · 不会下单或扣款", systemImage: "shield.lefthalf.filled")
            .font(.footnote.weight(.medium)).foregroundStyle(CoffeeTheme.blue).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(CoffeeTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var turn = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ModeBanner()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今天，交给随机。") .font(.largeTitle.bold())
                        Text("从你喜欢的口味里，选一杯刚刚好。") .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 20) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 72)).foregroundStyle(CoffeeTheme.blue)
                            .rotationEffect(.degrees(store.busy && !reduceMotion ? (turn ? 6 : -6) : 0))
                            .animation(store.busy && !reduceMotion ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: turn)
                            .accessibilityHidden(true)
                        VStack(spacing: 6) {
                            Text(store.pool.name).font(.title2.bold())
                            Text("\(store.pool.candidates.filter(\.enabled).count) 款启用饮品 · \(store.pool.weighted ? "加权随机" : "等概率随机")").foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack(alignment: .top) {
                            Label(store.data.configuration.shop?.name ?? "尚未选择门店", systemImage: "mappin.and.ellipse")
                            Spacer(minLength: 16)
                            Text("每杯 ≤ \(money(store.data.configuration.limits.cup))").monospacedDigit()
                        }.font(.subheadline)
                        Button { Task { turn.toggle(); await store.buy() } } label: {
                            HStack { if store.busy { ProgressView() }; Label(store.busy ? store.phase : "随机买一杯", systemImage: "shuffle").font(.headline) }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(.borderedProminent).disabled(store.busy || store.pool.candidates.filter(\.enabled).isEmpty)
                        Button("只抽取并预览价格") { Task { await store.buy(previewOnly: true) } }.disabled(store.busy)
                    }.padding(24).background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 24))
                    if store.pool.candidates.isEmpty {
                        ContentUnavailableView { Label("先放入你喜欢的咖啡", systemImage: "plus.circle") } description: { Text("在咖啡池中搜索饮品，配置口味后添加。首次可用模拟菜单走完流程。") } actions: { Button("去挑选饮品") { store.selectedTab = 1 } }
                    }
                    if let draw = store.data.draws.first {
                        VStack(alignment: .leading, spacing: 8) { Text("上次抽中").font(.caption).foregroundStyle(.secondary); Text(draw.name).font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("优惠、库存与可选规格以官方实时预览为准。支付身份验证由官方支付渠道完成。").font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.background(CoffeeTheme.background).navigationTitle("Luckin Random").navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct PoolsView: View {
    @EnvironmentObject var store: AppStore
    @State private var menu = false; @State private var newPool = false; @State private var name = ""
    @State private var editing: Candidate?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("当前咖啡池", selection: $store.data.configuration.selectedPoolId) { ForEach(store.data.configuration.pools) { Text($0.name).tag($0.id) } }
                    Toggle("避免连续两次重复", isOn: Binding(get: { store.pool.avoidRepeat }, set: { var p = store.pool; p.avoidRepeat = $0; store.replacePool(p) }))
                    Toggle("使用随机权重", isOn: Binding(get: { store.pool.weighted }, set: { var p = store.pool; p.weighted = $0; store.replacePool(p) }))
                } footer: { Text("默认等概率。仅有一款可用饮品时允许重复；不可用候选每轮最多尝试一次。") }
                Section("候选饮品 · \(store.pool.candidates.count)") {
                    if store.pool.candidates.isEmpty { Text("还没有候选饮品，点击右上角添加。").foregroundStyle(.secondary) }
                    ForEach(store.pool.candidates) { c in
                        Button { editing = c } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: c.enabled ? "cup.and.saucer" : "pause.circle").foregroundStyle(CoffeeTheme.blue).frame(width: 32, height: 44).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) { Text(c.name).foregroundStyle(.primary); Text(c.summary.isEmpty ? "门店默认规格" : c.summary).font(.caption).foregroundStyle(.secondary); if !c.enabled { Text("已暂停").font(.caption) } }
                                Spacer(); Text(probability(c)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("删除", role: .destructive) { var p = store.pool; p.candidates.removeAll { $0.id == c.id }; store.replacePool(p) } }
                    }
                }
                Section {
                    Button("新建咖啡池", systemImage: "plus") { newPool = true }
                    if store.data.configuration.pools.count > 1 { Button("删除当前咖啡池", role: .destructive) { store.removePool(store.pool.id) } }
                }
            }.navigationTitle("我的咖啡池")
                .toolbar { Button("添加饮品", systemImage: "plus") { menu = true } }
                .sheet(isPresented: $menu) { NavigationStack { MenuView().environmentObject(store) } }
                .sheet(item: $editing) { c in NavigationStack { CandidateEditor(candidate: c).environmentObject(store) } }
                .alert("新建咖啡池", isPresented: $newPool) { TextField("名称", text: $name); Button("创建") { store.addPool(name); name = "" }; Button("取消", role: .cancel) {} }
        }
    }
    func probability(_ c: Candidate) -> String {
        guard c.enabled else { return "暂停" }
        let all = store.pool.candidates.filter(\.enabled)
        let p = store.pool.weighted ? c.weight / max(all.map(\.weight).reduce(0,+), 1) : 1 / Double(max(all.count,1))
        return p.formatted(.percent.precision(.fractionLength(0)))
    }
}
struct MenuView: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    @State private var query = ""; @State private var products: [Product] = []; @State private var category = "全部"
    @State private var selected = Set<String>(); @State private var detail: Product?; @State private var fetching = false
    var body: some View {
        List {
            Section {
                Text(store.data.configuration.shop?.name ?? "请先在设置中选择门店").font(.headline)
                if store.data.useBackend { Text("当前官方文档仅证实商品搜索，完整菜单和分类待接口验证。").font(.footnote).foregroundStyle(.secondary) }
                HStack { TextField("搜索喜欢的饮品", text: $query).submitLabel(.search).onSubmit(search); Button("搜索", action: search).disabled(fetching) }
                Picker("分类", selection: $category) { ForEach(["全部"] + Array(Set(products.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }
            }
            if fetching { ProgressView("读取门店商品") }
            ForEach(products.filter { category == "全部" || $0.category == category }) { p in
                HStack(spacing: 12) {
                    Button { if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) } } label: { Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("\(selected.contains(p.id) ? "取消选择" : "选择")\(p.name)")
                    ProductThumb(url: p.image)
                    Button { store.perform { detail = try await store.detail(p.id) } } label: { VStack(alignment: .leading, spacing: 4) { Text(p.name).foregroundStyle(.primary); Text("预估 \(money(p.estimateCents)) · 查看规格").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.borderless)
                }.padding(.vertical, 4)
            }
            if !fetching && products.isEmpty { ContentUnavailableView("搜索一款你喜欢的饮品", systemImage: "magnifyingglass", description: Text("真实商品和规格从所选门店查询；模拟模式仅显示测试数据。")) }
        }.navigationTitle("挑选饮品").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("添加 \(selected.count) 款") { for p in products where selected.contains(p.id) { store.add(p) }; selected.removeAll() }.disabled(selected.isEmpty) } }
            .sheet(item: $detail) { p in NavigationStack { ProductEditor(product: p).environmentObject(store) } }
            .task { if !store.data.useBackend { if store.data.configuration.shop == nil { store.data.configuration.shop = MockCatalog.shop }; search() } }
    }
    func search() { fetching = true; store.perform { defer { fetching = false }; products = try await store.products(query); selected.removeAll() } }
}
struct ProductThumb: View {
    let url: String?
    var body: some View {
        Group {
            if let url, let u = URL(string: url), u.scheme == "https" { AsyncImage(url: u) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "cup.and.saucer") } }
            else { Image(systemName: "cup.and.saucer").font(.title2).foregroundStyle(CoffeeTheme.blue) }
        }.frame(width: 52, height: 60).background(CoffeeTheme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
    }
}
struct ProductEditor: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    @State var product: Product; @State private var changing = false
    var body: some View {
        Form {
            Section { Text(product.name).font(.title2.bold()); Text("预估价格 \(money(product.estimateCents))"); Text("每次下单前都会重新查询规格与官方预览。").font(.footnote).foregroundStyle(.secondary) }
            ForEach(product.attributes) { a in
                Section(a.name) {
                    ForEach(a.options) { o in
                        Button { choose(a, o) } label: { HStack { Text(o.name).foregroundStyle(.primary); Spacer(); if o.selected { Image(systemName: "checkmark") } } }.disabled(changing || !o.available)
                    }
                }
            }
            Section { Button("加入当前咖啡池") { store.add(product); dismiss() }.disabled(changing) }
        }.navigationTitle("选择口味").navigationBarTitleDisplayMode(.inline).toolbar { Button("关闭") { dismiss() } }
    }
    func choose(_ a: DrinkAttribute, _ o: DrinkOption) {
        changing = true
        store.perform { defer { changing = false }
            if store.data.useBackend {
                var prefs = product.attributes.flatMap { group in group.options.filter(\.selected).map { Preference(group: group.id, option: $0.id, label: $0.name) } }
                prefs.removeAll { $0.group == a.id }; prefs.append(Preference(group: a.id, option: o.id, label: o.name))
                product = try await store.detail(product.id, preferences: prefs)
            } else if let n = product.attributes.firstIndex(where: { $0.id == a.id }) {
                for i in product.attributes[n].options.indices { product.attributes[n].options[i].selected = product.attributes[n].options[i].id == o.id }
                product.sku = "MOCK-\(product.id)-" + product.attributes.flatMap { $0.options.filter(\.selected).map { String($0.id) } }.joined(separator: "-")
            }
        }
    }
}
struct CandidateEditor: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    @State var candidate: Candidate; @State private var product: Product?
    var body: some View {
        Form {
            Section(candidate.name) { Toggle("参与随机", isOn: $candidate.enabled); Text(candidate.summary.isEmpty ? "门店默认规格" : candidate.summary); TextField("自定义备注", text: $candidate.note, axis: .vertical); Stepper("随机权重 \(candidate.weight.formatted())", value: $candidate.weight, in: 1...10000, step: 1) }
            Section {
                Button("重新查询并编辑规格") { store.perform { product = try await store.detail(candidate.productId) } }
                Text("新规格会以新候选添加，请确认后删除旧候选。修改备注不改变官方规格。").font(.footnote).foregroundStyle(.secondary)
                Button("保存") { var p = store.pool; if let n = p.candidates.firstIndex(where: { $0.id == candidate.id }) { p.candidates[n] = candidate; store.replacePool(p) }; dismiss() }
                Button("删除饮品", role: .destructive) { var p = store.pool; p.candidates.removeAll { $0.id == candidate.id }; store.replacePool(p); dismiss() }
            }
        }.navigationTitle("饮品偏好").toolbar { Button("取消") { dismiss() } }.sheet(item: $product) { p in NavigationStack { ProductEditor(product: p).environmentObject(store) } }
    }
}
