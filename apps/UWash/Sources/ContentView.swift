import SwiftUI

let washTint = Color(red: 0.23, green: 0.22, blue: 0.69)

struct ContentView: View {
    @StateObject private var session = LaundrySession()
    @State private var login = false
    @State private var payment = false
    var body: some View {
        TabView {
            NavigationStack { WashScreen(session: session, login: $login).navigationTitle("净洗") }.tabItem { Label("洗衣", systemImage: "washer") }
            NavigationStack { OrdersScreen(session: session, login: $login).navigationTitle("洗衣订单") }.tabItem { Label("订单", systemImage: "list.bullet.rectangle") }
            NavigationStack { account.navigationTitle("账号") }.tabItem { Label("账号", systemImage: "person.crop.circle") }
        }
        .tint(washTint)
        .safeAreaInset(edge: .bottom) {
            if session.busy { HStack(spacing: 10) { ProgressView(); Text("正在处理，请稍候…").font(.callout) }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .alert("操作未完成", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(session.error ?? "") }
        .sheet(isPresented: $login) { LoginSheet(session: session) }
        .sheet(isPresented: $payment) {
            NavigationStack {
                if let url = session.payURL {
                    PaymentWeb(url: url, failure: { session.error = $0 })
                        .navigationTitle("支付").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("返回订单") { payment = false; session.payURL = nil } } }
                }
            }
        }
        .onChange(of: session.payURL) { _, url in
            guard let url else { return }
            if url.scheme == "https" { payment = true }
            else { UIApplication.shared.open(url) { opened in if !opened { session.error = "未能打开支付 App。请先刷新订单并核对结果。" } }; session.payURL = nil }
        }
    }
    private var account: some View {
        Form {
            Section("U净账号") {
                LabeledContent("状态", value: session.loggedIn ? "会话已保存" : "未登录")
                Button(session.loggedIn ? "重新登录" : "登录 U净") { login = true }.disabled(session.busy)
                if session.loggedIn { Button("退出并清除本机登录", role: .destructive) { session.logout() }.disabled(session.busy) }
            }
            Section("关于净洗") {
                Text("只保留自助洗衣入口：扫码识别、程序选择和洗衣订单。")
                Text("基于 U净 2.4.15 APK 洗衣模块重建的个人测试客户端，与官方 U净无隶属关系。")
                LabeledContent("版本", value: "0.1.0 (1)")
                Text("蓝牙机型、官方支付 SDK 及完整真机流程仍待适配验证。").foregroundStyle(.secondary)
            }
            Section {
                Link("U净隐私政策", destination: URL(string: "https://wx.zhinengxiyifang.cn/about_us/privacy_policy.html")!)
                Link("官方洗衣入口", destination: URL(string: "https://wx.zhinengxiyifang.cn/")!)
            }
        }
    }
}

struct WashScreen: View {
    @ObservedObject var session: LaundrySession
    @Binding var login: Bool
    @State private var scanner = false
    @State private var qr = ""
    @State private var byID = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "washer.fill").font(.system(size: 45)).foregroundStyle(washTint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) { Text("把时间留给自己").font(.title3.bold()); Text("扫码选机，安心洗衣").foregroundStyle(.secondary) }
                }.padding(.vertical, 16)
                Button { session.loggedIn ? (scanner = true) : (login = true) } label: { Label(session.loggedIn ? "扫码洗衣" : "登录后扫码洗衣", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).disabled(session.busy)
            }
            Section("手动识别") {
                Picker("输入内容", selection: $byID) { Text("二维码内容").tag(false); Text("设备 ID").tag(true) }.pickerStyle(.segmented)
                TextField(byID ? "服务端设备 ID（非机身编号）" : "粘贴洗衣机二维码链接", text: $qr, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4).accessibilityLabel(byID ? "设备 ID" : "二维码内容")
                Button("识别设备", action: identify).disabled(session.busy || qr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !session.note.isEmpty { Section { Label(session.note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled) } }
            if !session.device["deviceId"].text.isEmpty { DevicePanel(session: session).id(session.device["deviceId"].text) }
            if !session.order["orderId"].text.isEmpty { OrderPanel(session: session) }
        }
        .sheet(isPresented: $scanner) {
            NavigationStack {
                QRScanner(result: { value in qr = value; byID = false; scanner = false; identify() }, failure: { message in scanner = false; session.error = message })
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) { Text("对准洗衣机上的二维码").font(.headline).padding().background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 40) }
                    .navigationTitle("扫码洗衣").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { scanner = false } } }
            }
        }
    }
    private func identify() {
        guard session.loggedIn else { login = true; return }
        session.perform { try await session.identify(qr, isDeviceID: byID) }
    }
}

struct DevicePanel: View {
    @ObservedObject var session: LaundrySession
    @State private var selected = ""
    @State private var extras: [String: JSON] = [:]
    @State private var confirm = false
    private var program: JSON { session.programs.first { $0["workModelId"].text == selected } ?? .null }
    private var groups: [JSON] { program["additionDevices"]["washingPartnerFeature"].list + program["additionParams"].list }
    private var bluetooth: Bool { LaundryProtocol.bluetoothRequired(session.device) || LaundryProtocol.bluetoothRequired(session.scan) }
    var body: some View {
        Group {
            Section("已识别的洗衣机") {
                LabeledContent("设备", value: session.device.firstText("deviceNo", "deviceId"))
                LabeledContent("门店", value: session.device["storeName"].text)
                LabeledContent("机型", value: session.device["deviceTypeName"].text)
                if !session.device["warmTip"].text.isEmpty { Text(session.device["warmTip"].text).foregroundStyle(.secondary) }
                if !session.device["notification"]["content"].text.isEmpty { Text(session.device["notification"]["content"].text) }
                if bluetooth { Label("此设备需专用蓝牙控制，本版暂不支持下单和启动。", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
            Section("选择洗衣程序") {
                ForEach(Array(session.programs.enumerated()), id: \.offset) { _, p in
                    Button { selected = p["workModelId"].text } label: {
                        HStack {
                            Image(systemName: selected == p["workModelId"].text ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.firstText("workModelName", "name"))
                                if !p["time"].text.isEmpty { Text("约 \(p["time"].text) 分钟").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(); Text(price(p)).monospacedDigit()
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == p["workModelId"].text ? .isSelected : [])
                }
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section(group.firstText("name", "title", "key")) {
                    let key = group["key"].text
                    Picker("附加项目", selection: Binding(get: { extras[key]?.text ?? "" }, set: { newValue in extras[key] = group["options"].list.first { $0["id"].text == newValue }?["id"] })) {
                        Text("不选择").tag("")
                        ForEach(Array(group["options"].list.enumerated()), id: \.offset) { _, option in
                            Text("\(option.firstText("name", "gearName", "title")) · \(LaundryProtocol.money(option["isPromotion"].flag ? option["promotionPrice"] : option["price"]))").tag(option["id"].text)
                        }
                    }
                }
            }
            Section {
                Button("创建洗衣订单") { confirm = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                    .disabled(session.busy || selected.isEmpty || bluetooth || !LaundryProtocol.networkControlSupported(session.device) || session.device["type"].integer != 1 || session.device["notification"]["usageLimit"].integer == 1)
            } footer: { Text("下单前请核对设备、程序和附加项目。最终金额由 U净服务端计算。") }
        }
        .onChange(of: selected) { _, _ in extras = [:] }
        .confirmationDialog("确认创建洗衣订单？", isPresented: $confirm, titleVisibility: .visible) {
            Button("创建订单并核对付款") { session.perform { try await session.create(program: program, extras: extras) } }
            Button("取消", role: .cancel) {}
        } message: { Text("\(program.firstText("workModelName", "name")) · \(price(program))，附加项目以服务器最终账单为准。") }
    }
    private func price(_ p: JSON) -> String { LaundryProtocol.money(p["isPromotion"].flag ? p["promotionPrice"] : p["basePrice"]) }
}

struct OrderPanel: View {
    @ObservedObject var session: LaundrySession
    @State private var confirmCancel = false
    @State private var command = ""
    @State private var confirmControl = false
    @State private var confirmPay = false
    @State private var payMethod: JSON = .null
    @State private var useBalance = false
    private var order: JSON { session.order }
    var body: some View {
        Group {
            Section("订单详情") {
                LabeledContent("订单", value: order["orderId"].text).textSelection(.enabled)
                LabeledContent("状态", value: LaundryProtocol.status(order))
                if !order["deviceNo"].text.isEmpty { LabeledContent("设备", value: order["deviceNo"].text) }
                if !order["storeName"].text.isEmpty { LabeledContent("门店", value: order["storeName"].text) }
                if !order["workModelName"].text.isEmpty { LabeledContent("程序", value: order["workModelName"].text) }
                if !order["price"].text.isEmpty { LabeledContent("订单金额", value: LaundryProtocol.money(order["price"])) }
                if !order["remainingTime"].text.isEmpty { LabeledContent("剩余时间", value: order["remainingTime"].text) }
                Button("刷新此订单") { session.perform { try await session.loadOrder(order["orderId"].text) } }.disabled(session.busy)
            }
            if order["status"].text == "10" {
                Section("付款") {
                    Button("查询可用支付方式") { session.perform { try await session.loadPaymentMethods() } }.disabled(session.busy)
                    if !session.paymentMethods.isEmpty {
                        Toggle("使用 U净余额红包抵扣", isOn: $useBalance)
                        ForEach(Array(session.paymentMethods.enumerated()), id: \.offset) { _, method in Button(method.firstText("name", "channel")) { payMethod = method; confirmPay = true }.disabled(session.busy) }
                    }
                    Button("取消订单", role: .destructive) { confirmCancel = true }.disabled(session.busy)
                } footer: { Text("仅显示本版能处理的网页支付渠道；官方 App SDK 支付尚未接入。") }
            }
            if LaundryProtocol.bluetoothRequired(order) {
                Section { Text("这台设备需要专用蓝牙协议，请在官方 U净完成启动。") }
            } else if LaundryProtocol.networkControlSupported(order), ["20", "35", "40"].contains(order["status"].text) {
                Section("控制设备") {
                    if ["20", "35"].contains(order["status"].text) { controlButton("start") }
                    if order["status"].text == "40" { controlButton("stop") }
                } footer: { Text("指令受理后请观察机器实际状态。") }
            }
        }
        .confirmationDialog("确认取消此订单？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("取消订单", role: .destructive) { session.perform { try await session.cancelOrder() } }
            Button("返回", role: .cancel) {}
        } message: { Text("退款与取消结果以 U净服务端为准。") }
        .confirmationDialog("确认发送机器指令？", isPresented: $confirmControl, titleVisibility: .visible) {
            Button(commandName) { session.perform { try await session.control(command) } }
            Button("取消", role: .cancel) {}
        } message: { Text("请确认衣物已放好、机门已关，并核对设备编号 \(order["deviceNo"].text)。") }
        .confirmationDialog("确认发起支付？", isPresented: $confirmPay, titleVisibility: .visible) {
            Button("前往支付") { session.perform { try await session.pay(channel: payMethod, useBalance: useBalance) } }
            Button("取消", role: .cancel) {}
        } message: { Text("订单 \(order["orderId"].text)。请核对账单，金额以支付页为准。返回后刷新订单确认结果。") }
    }
    private var commandName: String { command == "stop" ? "停止洗衣" : "启动洗衣" }
    private func controlButton(_ value: String) -> some View { Button(value == "stop" ? "停止洗衣" : "启动洗衣", role: value == "stop" ? .destructive : nil) { command = value; confirmControl = true }.disabled(session.busy) }
}

struct OrdersScreen: View {
    @ObservedObject var session: LaundrySession
    @Binding var login: Bool
    var body: some View {
        List {
            if !session.loggedIn { Section { Button("登录后查看洗衣订单") { login = true } } }
            else {
                Section { Button("刷新订单") { session.perform { try await session.loadOrders(page: session.historyPage) } }.disabled(session.busy) }
                if !session.ordersError.isEmpty { Section { Text(session.ordersError).foregroundStyle(.orange) } }
                if !session.ordersLoaded { Section { Text("点刷新读取 U净洗衣订单。").foregroundStyle(.secondary) } }
                else {
                    Section("进行中") { if session.running.isEmpty { Text("暂无进行中的订单").foregroundStyle(.secondary) }; rows(session.running) }
                    Section("历史订单 · 第 \(session.historyPage) 页") { if session.history.isEmpty { Text("本页暂无订单").foregroundStyle(.secondary) }; rows(session.history) }
                    Section {
                        HStack { Button("上一页") { session.perform { try await session.loadOrders(page: max(1, session.historyPage - 1)) } }.disabled(session.busy || session.historyPage == 1); Spacer(); Button("下一页") { session.perform { try await session.loadOrders(page: session.historyPage + 1) } }.disabled(session.busy || session.history.count < 20) }
                    }
                }
                if !session.order["orderId"].text.isEmpty { OrderPanel(session: session) }
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
    @State private var mobile = ""
    @State private var code = ""
    @State private var accepting = false
    @State private var failure = ""
    @State private var sent = false
    @State private var nextCodeDate = Date.distantPast
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("登录后即可识别洗衣机、选择程序和查看订单。").foregroundStyle(.secondary)
                    TextField("手机号", text: $mobile).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityLabel("手机号")
                    TextField("短信验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).accessibilityLabel("短信验证码")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil(nextCodeDate.timeIntervalSince(context.date))))
                        Button(remaining > 0 ? "\(remaining) 秒后可重发" : "获取验证码") {
                            accepting = true; failure = ""
                            Task {
                                defer { accepting = false }
                                do { try await browser.sendCode(mobile: mobile); sent = true; nextCodeDate = Date().addingTimeInterval(60) }
                                catch { failure = "验证码请求失败，请稍后重试。" }
                            }
                        }.disabled(accepting || !browser.ready || remaining > 0 || mobile.count != 11)
                    }
                    if sent { Text("验证码已发送，请查看手机短信。").foregroundStyle(.secondary) }
                } header: { Text("U净账号") } footer: { Text("验证码仅由你点击后发送。登录会话保存在本机钥匙串。") }
                Section {
                    Button("登录") {
                        accepting = true; failure = ""
                        Task {
                            defer { accepting = false }
                            do { try await session.login(mobile: mobile, code: code); code = ""; dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent).disabled(accepting || mobile.count != 11 || code.isEmpty)
                    if accepting { ProgressView("正在处理…") }
                    if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
                    if !browser.error.isEmpty { Text(browser.error).foregroundStyle(.red) }
                    if !browser.ready { Button("重新加载验证码组件") { browser.error = ""; browser.view.reload() }.disabled(accepting) }
                }
                Section { Link("U净隐私政策", destination: URL(string: "https://wx.zhinengxiyifang.cn/about_us/privacy_policy.html")!) }
            }
            .background { LoginWeb(browser: browser).frame(width: 1, height: 1).opacity(0.001).accessibilityHidden(true) }
            .navigationTitle("登录 U净").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(accepting) } }
            .interactiveDismissDisabled(accepting)
        }
    }
}
