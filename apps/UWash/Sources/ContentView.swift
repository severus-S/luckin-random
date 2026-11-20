import SwiftUI

let washTint = Color(red: 0.23, green: 0.22, blue: 0.69)

struct ContentView: View {
    @StateObject private var session = LaundrySession()
    @State private var login = false
    @State private var handoff = false
    var body: some View {
        TabView {
            NavigationStack { WashScreen(session: session, login: $login, launch: { handoff = true }).navigationTitle("净洗") }.tabItem { Label("洗衣", systemImage: "washer") }
            NavigationStack { OrdersScreen(session: session, login: $login).navigationTitle("洗衣订单") }.tabItem { Label("订单", systemImage: "list.bullet.rectangle") }
            NavigationStack { account.navigationTitle("账号") }.tabItem { Label("账号", systemImage: "person.crop.circle") }
        }
        .tint(washTint)
        .safeAreaInset(edge: .bottom) {
            if session.busy { HStack(spacing: 10) { ProgressView(); Text("正在读取…").font(.callout) }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .alert("操作未完成", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(session.error ?? "") }
        .sheet(isPresented: $login) { LoginSheet(session: session) }
        .confirmationDialog("前往 U净官方支付宝小程序？", isPresented: $handoff, titleVisibility: .visible) {
            Button("去选择程序并使用") {
                do { try session.openAlipay() }
                catch { session.error = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("请在支付宝中核对设备、洗衣程序和金额，确认后再付款。若未自动带入机器，请在小程序内重新扫码。") }
    }
    private var account: some View {
        Form {
            Section("U净账号") {
                LabeledContent("状态", value: session.loggedIn ? "会话已保存" : "未登录")
                Button(session.loggedIn ? "重新网页登录 U净" : "网页登录 U净") { login = true }.disabled(session.busy)
                if session.loggedIn { Button("退出并清除本机登录", role: .destructive) { session.logout() }.disabled(session.busy) }
                Text("先完成官方网页登录，再扫码识别洗衣机。登录会话保存在本机钥匙串。").font(.callout).foregroundStyle(.secondary)
            }
            Section("关于净洗") {
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                Text("洗衣程序、洗护用品、下单、支付和设备操作由 U净官方支付宝小程序处理。净洗提供网页登录、扫码识别和订单读取。")
                Text("首次使用请在支付宝中核对机器。若未自动带入，请用小程序内的扫一扫。").foregroundStyle(.secondary)
                Link("U净隐私政策", destination: URL(string: "https://wx.zhinengxiyifang.cn/about_us/privacy_policy.html")!)
            }
        }
    }
}

struct WashScreen: View {
    @ObservedObject var session: LaundrySession
    @Binding var login: Bool
    let launch: () -> Void
    @State private var scanner = false
    @State private var qr = ""
    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "washer.fill").font(.system(size: 45)).foregroundStyle(washTint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) { Text("扫一扫，开始洗衣").font(.title3.bold()); Text("选择程序和支付交给 U净小程序").foregroundStyle(.secondary) }
                }.padding(.vertical, 16)
                Button { session.loggedIn ? (scanner = true) : (login = true) } label: { Label("扫码识别洗衣机", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).disabled(session.busy)
                if !session.loggedIn { Button("网页登录 U净") { login = true }.frame(minHeight: 44) }
            }
            Section("粘贴设备二维码") {
                TextField("洗衣机二维码的完整内容", text: $qr, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4).accessibilityLabel("洗衣机二维码内容").disabled(session.busy)
                Button("识别设备", action: identify).disabled(session.busy || qr.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !session.device.fields.isEmpty {
                Section("已识别的洗衣机") {
                    LabeledContent("设备", value: session.device.firstText("deviceName", "deviceNo", "deviceId"))
                    if !session.device["storeName"].text.isEmpty { LabeledContent("门店", value: session.device["storeName"].text) }
                    Text("已确认是洗衣机设备").foregroundStyle(.secondary)
                    Button("去支付宝选择程序并使用", action: launch).frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent).disabled(session.busy)
                }
            }
            if !session.note.isEmpty { Section { Label(session.note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) } }
            Section {
                Text("洗衣程序、付款和设备启动在 U净官方支付宝小程序内完成。返回后可在订单页刷新结果。").font(.callout).foregroundStyle(.secondary)
            }
        }
        .onChange(of: qr) { _, value in if value.trimmingCharacters(in: .whitespaces) != session.deviceQRCode { session.clearDevice() } }
        .sheet(isPresented: $scanner) {
            NavigationStack {
                QRScanner(result: { value in qr = value; scanner = false; identify() }, failure: { scanner = false; session.error = $0 })
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) { Text("对准 U净洗衣机二维码").font(.headline).padding().background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 40) }
                    .navigationTitle("扫码洗衣").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { scanner = false } } }
            }
        }
    }
    private func identify() {
        guard session.loggedIn else { login = true; return }
        session.perform { try await session.identify(qr) }
    }
}

struct OrdersScreen: View {
    @ObservedObject var session: LaundrySession
    @Binding var login: Bool
    var body: some View {
        List {
            if !session.loggedIn { Section { Button("网页登录 U净读取订单") { login = true } } }
            else {
                Section { Button("刷新订单") { session.perform { try await session.loadOrders(page: session.historyPage) } }.disabled(session.busy) }
                if !session.ordersError.isEmpty { Section { Text(session.ordersError).foregroundStyle(.orange) } }
                if !session.ordersLoaded { Section { Text("点刷新读取 U净订单。").foregroundStyle(.secondary) } }
                else {
                    Section("进行中") { if session.running.isEmpty { Text("暂无进行中的订单").foregroundStyle(.secondary) }; rows(session.running) }
                    Section("历史订单 · 第 \(session.historyPage) 页") { if session.history.isEmpty { Text("本页暂无订单").foregroundStyle(.secondary) }; rows(session.history) }
                    Section {
                        HStack { Button("上一页") { session.perform { try await session.loadOrders(page: max(1, session.historyPage - 1)) } }.disabled(session.busy || session.historyPage == 1); Spacer(); Button("下一页") { session.perform { try await session.loadOrders(page: session.historyPage + 1) } }.disabled(session.busy || session.history.count < 20) }
                    }
                }
                if !session.order["orderId"].text.isEmpty {
                    Section("订单快照") {
                        LabeledContent("订单", value: session.order["orderId"].text).textSelection(.enabled)
                        LabeledContent("状态", value: LaundryProtocol.status(session.order))
                        LabeledContent("设备", value: session.order["deviceNo"].text)
                        LabeledContent("门店", value: session.order["storeName"].text)
                        if !session.order["price"].text.isEmpty { LabeledContent("订单金额", value: LaundryProtocol.money(session.order["price"])) }
                        Button("刷新此订单") { session.perform { try await session.loadOrder(session.order["orderId"].text) } }.disabled(session.busy)
                    }
                }
            }
        }
    }
    @ViewBuilder private func rows(_ values: [JSON]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, row in
            Button { session.perform { try await session.loadOrder(row["orderId"].text) } } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(row.firstText("storeName", "deviceNo", "orderId")).font(.headline); Spacer(); Text(LaundryProtocol.status(row)).font(.callout).foregroundStyle(washTint) }
                    Text(row.firstText("workModelName", "deviceTypeName")).foregroundStyle(.secondary)
                    Text("订单 \(row["orderId"].text)").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(session.busy)
        }
    }
}

struct LoginSheet: View {
    @ObservedObject var session: LaundrySession
    @StateObject private var browser = LoginBrowser()
    @State private var accepting = false
    @State private var failure = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("请在 U净官方网页完成登录，再点右上角“完成登录”。").font(.callout).foregroundStyle(.secondary).padding()
                if browser.loading { ProgressView("正在加载官方登录页…").padding() }
                LoginWeb(browser: browser)
                if !failure.isEmpty { Text(failure).foregroundStyle(.red).font(.callout).padding() }
                if !browser.error.isEmpty { Text(browser.error).foregroundStyle(.orange).font(.callout).padding() }
                if accepting { ProgressView("正在验证登录…").padding() }
                Button("重新加载官方登录页") { browser.reload() }.disabled(accepting).padding()
            }
            .navigationTitle("网页登录 U净").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(accepting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") {
                        accepting = true; failure = ""
                        Task {
                            defer { accepting = false }
                            do { let token = try await browser.readToken(); try await session.acceptAccessToken(token); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.disabled(accepting || !browser.ready)
                }
            }
            .interactiveDismissDisabled(accepting)
        }
    }
}
