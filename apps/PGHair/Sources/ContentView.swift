import SwiftUI

private let hairBlue = Color(red: 0.08, green: 0.35, blue: 0.72)

struct ContentView: View {
    @StateObject private var session = HairSession()
    @State private var login = false
    @State private var scanner = false
    @State private var qr = ""
    @State private var handoff = false
    @State private var selectedOrder: OrderSelection?
    var body: some View {
        TabView {
            NavigationStack { deviceScreen.navigationTitle("轻吹") }.tabItem { Label("吹风", systemImage: "wind") }
            NavigationStack { orderScreen.navigationTitle("吹风订单") }.tabItem { Label("订单", systemImage: "list.bullet.rectangle") }
            NavigationStack { accountScreen.navigationTitle("账号") }.tabItem { Label("账号", systemImage: "person.crop.circle") }
        }
        .tint(hairBlue)
        .safeAreaInset(edge: .bottom) {
            if session.busy { HStack(spacing: 10) { ProgressView(); Text("正在读取…").font(.callout) }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .sheet(isPresented: $login) { LoginPanel(session: session) }
        .sheet(isPresented: $scanner) {
            NavigationStack {
                QRScanner(result: { value in qr = value; scanner = false; identify() }, failure: { scanner = false; session.error = $0 })
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) { Text("对准胖乖生活吹风机二维码").font(.headline).padding().background(.regularMaterial, in: Capsule()).padding(.bottom, 40) }
                    .navigationTitle("扫码吹风").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { scanner = false } } }
            }
        }
        .sheet(item: $selectedOrder) { item in orderDetail(item.row) }
        .alert("操作未完成", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(session.error ?? "") }
        .confirmationDialog("前往官方支付宝小程序？", isPresented: $handoff, titleVisibility: .visible) {
            Button("去选时长并使用") { do { try session.openAlipay() } catch { session.error = error.localizedDescription } }
            Button("取消", role: .cancel) {}
        } message: { Text("请在支付宝中核对设备、时长和金额，确认后再付款。轻吹不会自动下单或扣款。") }
    }
    private var deviceScreen: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "wind").font(.system(size: 48, weight: .medium)).foregroundStyle(hairBlue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) { Text("扫一扫，开始吹风").font(.title3.bold()); Text("只留下每天需要的功能").foregroundStyle(.secondary) }
                }.padding(.vertical, 18)
                Button { session.hasCredential ? (scanner = true) : (login = true) } label: { Label("扫码识别吹风机", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).disabled(session.busy)
            }
            Section("粘贴二维码") {
                TextField("吹风机二维码的完整链接", text: $qr, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4).accessibilityLabel("吹风机二维码链接")
                Button("识别设备", action: identify).disabled(session.busy || qr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !session.device.fields.isEmpty {
                Section("已识别的吹风机") {
                    LabeledContent("设备", value: session.device.firstText("name", "machineName", "goodsName"))
                    if !session.device["orgName"].text.isEmpty { LabeledContent("门店", value: session.device["orgName"].text) }
                    Text("已确认是吹风机设备").foregroundStyle(.secondary)
                    Button("去支付宝选时长并使用") { handoff = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent).disabled(session.busy)
                }
            }
            if !session.note.isEmpty { Section { Label(session.note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled) } }
            Section {
                Text("时长选择、付款和设备启动在胖乖官方支付宝小程序内完成。返回后可在订单页刷新结果。").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var orderScreen: some View {
        List {
            if !session.hasCredential { Section { Button("登录后查看吹风订单") { login = true } } }
            else {
                Section { Button("刷新订单") { session.perform { try await session.refreshOrders(session.page) } }.disabled(session.busy) }
                if !session.ordersLoaded { Section { Text("点刷新读取账号的吹风机订单。").foregroundStyle(.secondary) } }
                else {
                    Section("第 \(session.page) 页") {
                        if session.orders.isEmpty { Text("本页未识别到吹风机订单").foregroundStyle(.secondary) }
                        ForEach(Array(session.orders.enumerated()), id: \.offset) { _, row in
                            Button { selectedOrder = OrderSelection(row: row) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(row.firstText("machineName", "goodsName", "name", "orderNo")).font(.headline)
                                    if !row["createTime"].text.isEmpty { Text(row["createTime"].text).font(.callout).foregroundStyle(.secondary) }
                                    HStack { Text(row.firstText("orderStatusName", "statusName").isEmpty ? "服务端状态：\(row["orderStatus"].text)" : row.firstText("orderStatusName", "statusName")); Spacer(); Text(HairPolicy.money(row["payPrice"])) }.font(.callout).foregroundStyle(.secondary)
                                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Section {
                        HStack {
                            Button("上一页") { session.perform { try await session.refreshOrders(max(1, session.page - 1)) } }.disabled(session.busy || session.page <= 1)
                            Spacer()
                            Button("下一页") { session.perform { try await session.refreshOrders(session.page + 1) } }.disabled(session.busy || !session.canNext)
                        }
                    } footer: { Text("只显示明确归类为吹风机的记录。服务端按全部订单分页，空页不代表没有其他吹风订单。") }
                }
            }
        }
    }
    private var accountScreen: some View {
        Form {
            Section("胖乖账号") {
                LabeledContent("状态", value: session.verified ? "账号已验证" : session.hasCredential ? "会话已保存，待刷新" : "未登录")
                if session.verified {
                    LabeledContent("手机号", value: HairPolicy.maskedPhone(session.account["phone"].text))
                    LabeledContent("通用余额", value: HairPolicy.money(session.account["balance"]))
                }
                Button(session.hasCredential ? "重新登录" : "登录胖乖生活") { login = true }.disabled(session.busy)
                if session.hasCredential {
                    Button("刷新账号和余额") { session.perform { try await session.refreshAccount() } }.disabled(session.busy)
                    Button("退出并清除本机登录", role: .destructive) { session.logout(); qr = "" }.disabled(session.busy)
                }
            }
            Section("关于轻吹") {
                LabeledContent("版本", value: "0.1.0 (1)")
                Text("胖乖生活吹风机专用个人客户端。提供扫码识别、官方使用入口、吹风订单和账号余额。")
                Text("与胖乖生活无隶属关系。时长与支付使用官方支付宝流程，实际登录、付款和设备运行仍需手机验证。").foregroundStyle(.secondary)
                Link("胖乖隐私政策", destination: URL(string: "https://h5.qiekj.com/user/UserAgreement/userPrivacy/legalPrivacy")!)
            }
        }
    }
    private func identify() {
        guard session.hasCredential else { login = true; return }
        session.perform { try await session.identify(qr) }
    }
    private func orderDetail(_ row: JSON) -> some View {
        NavigationStack {
            Form {
                Section("订单记录") {
                    LabeledContent("订单号", value: row.firstText("orderNo", "id")).textSelection(.enabled)
                    LabeledContent("设备", value: row.firstText("machineName", "goodsName", "name"))
                    LabeledContent("时间", value: row["createTime"].text)
                    LabeledContent("实付", value: HairPolicy.money(row["payPrice"]))
                    LabeledContent("服务端状态", value: row.firstText("orderStatusName", "statusName", "orderStatus"))
                }
                Section { Text("此处是最近一次刷新取得的记录。需要处理订单或查看实时倒计时，请在胖乖官方支付宝小程序内查看。").foregroundStyle(.secondary) }
            }
            .navigationTitle("吹风订单").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { selectedOrder = nil } } }
        }
    }
}

private struct OrderSelection: Identifiable { let id = UUID(); let row: JSON }

private struct LoginPanel: View {
    @ObservedObject var session: HairSession
    @StateObject private var browser = HairLogin()
    @State private var working = false
    @State private var failure = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("在官方网页完成验证码登录，再点击“完成登录”。支付宝小程序可能还需绑定相同手机号。").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding()
                if !failure.isEmpty { Text(failure).font(.callout).foregroundStyle(.red).padding(.horizontal) }
                if !browser.error.isEmpty { Text(browser.error).font(.callout).foregroundStyle(.secondary).padding(.horizontal) }
                HairLoginWeb(browser: browser)
                if working || browser.loading { ProgressView(working ? "正在验证账号…" : "正在加载登录页…").padding() }
            }
            .navigationTitle("登录胖乖生活").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") {
                        working = true; failure = ""
                        Task {
                            defer { working = false }
                            do { let token = try await browser.readToken(); try await session.accept(token); dismiss() }
                            catch let e as HairError { failure = e.message }
                            catch { failure = "读取登录结果失败，请完成网页登录后重试。" }
                        }
                    }.disabled(working || browser.loading)
                }
                ToolbarItem(placement: .bottomBar) { Button("重新加载") { browser.error = ""; browser.loading = true; browser.view.load(URLRequest(url: HairPolicy.loginURL)) }.disabled(working) }
            }
            .interactiveDismissDisabled(working)
        }
    }
}
