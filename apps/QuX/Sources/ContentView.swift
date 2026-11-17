import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    @AppStorage("qux.appearance") private var appearance = "跟随系统"
    @Environment(\.openURL) private var openURL
    @State private var snapshot: ParcelSnapshot?
    @State private var group: ParcelGroup = .pickup
    @State private var search = ""
    @State private var page: CainiaoPage?
    @State private var shareSelection: [PickupSection]?
    @State private var notice: String?
    @State private var confirmClear = false
    @State private var clearing = false

    private var parcels: [Parcel] { snapshot?.parcels ?? [] }
    private var pickupSections: [PickupSection] {
        PickupSection.grouped(parcels.filter { $0.group == .pickup && !$0.pickupCode.isEmpty })
    }
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "浅色": .light
        case "深色": .dark
        default: nil
        }
    }

    var body: some View {
        TabView {
            NavigationStack { parcelList }
                .tabItem { Label("包裹", systemImage: "shippingbox") }
            NavigationStack { account }
                .tabItem { Label("账号", systemImage: "person.crop.circle") }
            NavigationStack { settings }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.blue)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(colorScheme)
        .sheet(item: $page) { route in
            CainiaoSheet(page: route, save: save)
        }
        .sheet(isPresented: Binding(
            get: { shareSelection != nil },
            set: { if !$0 { shareSelection = nil } }
        )) {
            if let shareSelection { PickupShareView(sections: shareSelection) }
        }
        .alert("取X", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .confirmationDialog("清除本机包裹及网页会话？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除本机数据", role: .destructive) {
                Task { await clear() }
            }
        }
        .task {
            do {
                snapshot = try ParcelSnapshotFile.read()
            } catch {
                notice = "无法读取本机包裹，请重新同步。"
            }
        }
        .disabled(clearing)
    }

    private var parcelList: some View {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = parcels.filter { $0.group == group && $0.matches(term) }
        return GlassPage {
            VStack(alignment: .leading, spacing: 12) {
                Picker("包裹状态", selection: $group) {
                    ForEach(ParcelGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                if let snapshot {
                    Text("本机快照 · \(snapshot.syncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if filtered.isEmpty {
                GlassCard {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            term.isEmpty ? (snapshot == nil ? "同步你的包裹" : "暂无\(group.rawValue)包裹") : "没有匹配的包裹",
                            systemImage: term.isEmpty ? "shippingbox" : "magnifyingglass",
                            description: snapshot == nil && term.isEmpty ? Text("在菜鸟网页登录后同步。") : nil
                        )
                        if snapshot == nil && term.isEmpty {
                            Button("登录并同步包裹", systemImage: "arrow.clockwise") { page = .parcels }
                                .buttonStyle(.glassProminent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if group == .pickup {
                ForEach(PickupSection.grouped(filtered)) { section in
                    Text(section.name).font(.headline).padding(.horizontal, 4)
                    ForEach(section.parcels, content: parcelRow)
                }
            } else {
                ForEach(filtered, content: parcelRow)
            }
            if !term.isEmpty && term.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                Button {
                    page = .detail(mailNo: term)
                } label: {
                    Label("在菜鸟查询运单", systemImage: "arrow.up.right.square")
                }
            }
        }
        .navigationTitle("取X")
        .searchable(text: $search, prompt: "运单、驿站或取件码")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { page = .identity } label: { Label("身份码", systemImage: "barcode") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { page = .parcels } label: { Label("同步包裹", systemImage: "arrow.clockwise") }
                    Button { page = .pending } label: { Label("官方待取列表", systemImage: "tray") }
                    Button { shareSelection = pickupSections } label: {
                        Label("分享全部取件码", systemImage: "square.and.arrow.up")
                    }
                    .disabled(pickupSections.isEmpty)
                } label: {
                    Label("包裹操作", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func parcelRow(_ parcel: Parcel) -> some View {
        NavigationLink {
            GlassPage {
                if !parcel.pickupCode.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("取件码").font(.subheadline).foregroundStyle(.secondary)
                            Text(parcel.pickupCode)
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .textSelection(.enabled)
                            HStack(spacing: 12) {
                                Button("复制", systemImage: "document.on.document") {
                                    UIPasteboard.general.setItems(
                                        [[UTTypePlainText: parcel.pickupCode]], options: [.localOnly: true]
                                    )
                                    notice = "已复制取件码。"
                                }
                                Button("分享", systemImage: "square.and.arrow.up") {
                                    shareSelection = PickupSection.grouped([parcel])
                                }
                            }
                        }
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("包裹信息").font(.headline)
                        if !parcel.carrier.isEmpty { LabeledContent("快递公司", value: parcel.carrier) }
                        if !parcel.mailNo.isEmpty {
                            LabeledContent("运单号", value: parcel.mailNo).textSelection(.enabled)
                        }
                        if !parcel.station.isEmpty {
                            LabeledContent("取件点", value: parcel.station)
                            Button("在地图中搜索取件点") { openStation(parcel.station) }
                        }
                        LabeledContent("状态", value: parcel.displayStatus)
                        if !parcel.description.isEmpty { Text(parcel.description) }
                        if let time = parcel.updatedAt {
                            Text(time, format: .dateTime.month().day().hour().minute())
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !parcel.mailNo.isEmpty {
                    Button("查看官方物流详情") {
                        page = .detail(mailNo: parcel.mailNo, carrierCode: parcel.carrierCode, orderCode: parcel.orderCode)
                    }
                }
            }
            .navigationTitle(parcel.label)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            GlassCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(parcel.label).font(.headline)
                        if !parcel.pickupCode.isEmpty {
                            Text(parcel.pickupCode)
                                .font(.system(.title2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .accessibilityLabel("取件码 \(parcel.pickupCode)")
                        }
                        Text([parcel.carrier, parcel.displayStatus].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var account: some View {
        GlassPage {
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    Label("菜鸟账号", systemImage: "person.crop.circle.fill").font(.title2.bold())
                    Text("连接账号，集中查看包裹与取件信息。").foregroundStyle(.secondary)
                    Button("网页登录与同步", systemImage: "arrow.clockwise") { page = .parcels }
                        .buttonStyle(.glassProminent)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    Button { page = .parcels } label: {
                        Label("我的快递", systemImage: "shippingbox")
                    }
                    Button { page = .identity } label: {
                        Label("菜鸟身份码", systemImage: "barcode")
                    }
                    Button { page = .account } label: {
                        Label("菜鸟账号主页", systemImage: "person.crop.circle")
                    }
                    Button { page = .pending } label: {
                        Label("待取包裹", systemImage: "tray")
                    }
                }
            }
            Text("登录和验证由官方网页处理。切换账号前可在设置中清除本机数据。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .navigationTitle("账号")
    }

    private var settings: some View {
        GlassPage {
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("外观", selection: $appearance) {
                        ForEach(["跟随系统", "浅色", "深色"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    Divider()
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.8.2")
                }
            }
            GlassCard {
                Button("清除本机数据", role: .destructive) { confirmClear = true }
            }
        }
        .navigationTitle("设置")
    }

    private func save(_ parcels: [Parcel]) throws {
        let newSnapshot = ParcelSnapshot(syncedAt: .now, parcels: parcels)
        try ParcelSnapshotFile.save(newSnapshot)
        snapshot = newSnapshot
    }

    @MainActor
    private func clear() async {
        clearing = true
        defer { clearing = false }
        do {
            try ParcelSnapshotFile.clear()
            snapshot = nil
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
            )
        } catch {
            notice = "无法清除本机包裹，请重试。"
        }
    }

    private func openStation(_ station: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: station)]
        if let url = components.url { openURL(url) }
    }
}

private let UTTypePlainText = "public.utf8-plain-text"

private struct CainiaoSheet: View {
    let page: CainiaoPage
    let save: ([Parcel]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: CainiaoBrowser
    @State private var syncTask: Task<Void, Never>?
    @State private var showDiagnostics = false
    @State private var status: String?

    init(page: CainiaoPage, save: @escaping ([Parcel]) throws -> Void) {
        self.page = page
        self.save = save
        _browser = StateObject(wrappedValue: CainiaoBrowser(page: page))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = status ?? browser.message {
                    Text(message).font(.footnote).frame(maxWidth: .infinity).padding(10)
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .padding(.horizontal, 12)
                }
                if browser.loading { ProgressView().padding(8) }
                WebSurface(webView: browser.webView)
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.horizontal, 8)
            }
            .background { GlassBackdrop() }
            .safeAreaInset(edge: .bottom) {
                if browser.showingLogin {
                    Button("返回\(page.title)", systemImage: "arrow.uturn.backward") {
                        status = nil
                        browser.reload()
                    }
                    .buttonStyle(.glass)
                    .padding(12)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        syncTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if browser.canGoBack {
                        Button { browser.webView.goBack() } label: {
                            Label("网页后退", systemImage: "chevron.backward")
                        }
                        .disabled(syncTask != nil)
                    }
                    Button {
                        status = nil
                        browser.reload()
                    } label: {
                        Label("重新打开网页", systemImage: "arrow.clockwise")
                    }
                    .disabled(syncTask != nil)
                    if page.canSync {
                        Button("同步") { startSync() }
                            .disabled(!browser.canSync || syncTask != nil)
                    }
                    Menu {
                        Button("登录帮助与诊断", systemImage: "stethoscope") { showDiagnostics = true }
                        Button("检查菜鸟会话", systemImage: "checkmark.shield") {
                            status = nil
                            browser.verifySession()
                        }
                        Button("重新登录", systemImage: "person.crop.circle.badge.checkmark") {
                            status = nil
                            browser.login()
                        }
                        Button("返回\(page.title)", systemImage: "arrow.uturn.backward") {
                            status = nil
                            browser.reload()
                        }
                    } label: {
                        Label("登录操作", systemImage: "ellipsis")
                    }
                    .disabled(syncTask != nil)
                }
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("验证码后无法继续") .font(.headline)
                        Text("可在系统设置 → App → 取X中，尝试开启‘允许跨网站跟踪’，然后完全关闭取X再重开。该开关由系统控制，取X无法读取或修改它。")
                        Text("开启会降低本App内网页的跨站跟踪保护，可随时关闭。此项用于验证跨站Cookie兼容性，不代表已确定故障原因。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("打开取X系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.glass)
                        Divider()
                        Text("本次登录诊断").font(.headline)
                        Text("可复制报告仅记录域名、请求类别、状态和错误码。按调试要求，Xcode控制台另含完整导航URL与调用栈，可能包含登录票据，请勿公开分享。storage-no表示存储访问检查为否，不能单独证明故障原因。无手机号、验证码、请求正文、Cookie或票据。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(browser.diagnostics.isEmpty ? "尚未捕获登录事件。请返回登录页操作后再查看。" : browser.diagnostics.joined(separator: "\n"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                        Button("复制诊断") {
                            UIPasteboard.general.string = "取X 0.8.14 (21)\n" + browser.diagnostics.joined(separator: "\n")
                        }.disabled(browser.diagnostics.isEmpty)
                    }.padding()
                }
                .navigationTitle("登录帮助与诊断")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showDiagnostics = false } } }
            }
        }
        .onDisappear { syncTask?.cancel() }
    }

    private func startSync() {
        status = "正在读取包裹…"
        syncTask = Task { @MainActor in
            defer { syncTask = nil }
            let parcels: [Parcel]
            do {
                parcels = try await browser.readParcels()
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                if let failure = error as? CainiaoSession.Failure {
                    status = "同步接口未完成（\(failure.code)），已保留当前网页和本机包裹；可手动重新登录。"
                } else {
                    status = (error as? CainiaoSyncError)?.errorDescription ?? CainiaoSyncError.unavailable.errorDescription
                }
                return
            }
            do {
                try save(parcels)
                dismiss()
            } catch {
                status = "已收到包裹，但无法保存本机快照。"
            }
        }
    }
}

private struct WebSurface: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct PickupShareView: View {
    let sections: [PickupSection]
    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            GlassPage {
                ForEach(sections) { section in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(section.name).font(.headline)
                            ForEach(section.parcels) { parcel in
                                HStack {
                                    Text(parcel.pickupCode).font(.system(.headline, design: .monospaced))
                                    Spacer()
                                    Text(parcel.carrier).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("分享取件码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("分享") {
                        ShareLink(item: PickupSection.shareText(sections)) { Label("文本", systemImage: "text.alignleft") }
                        Button { renderImages() } label: { Label("图片", systemImage: "photo") }
                    }
                }
            }
        }
        .sheet(isPresented: $sharing, onDismiss: { images = [] }) {
            ActivitySheet(items: images)
        }
    }

    @MainActor
    private func renderImages() {
        let rows = sections.flatMap { section in section.parcels.map { (section.name, $0) } }
        let rendered = stride(from: 0, to: rows.count, by: 12).compactMap { index in
            let page = Array(rows[index..<min(index + 12, rows.count)])
            let renderer = ImageRenderer(content:
                VStack(alignment: .leading, spacing: 12) {
                    Text("取件码").font(.system(size: 22, weight: .bold))
                    ForEach(page.indices, id: \.self) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            if row == 0 || page[row].0 != page[row - 1].0 {
                                Text(page[row].0).font(.system(size: 15, weight: .semibold))
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text(page[row].1.pickupCode).font(.system(size: 25, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text(page[row].1.carrier).font(.system(size: 14))
                            }
                        }
                    }
                }
                .padding(24)
                .frame(width: 380)
                .foregroundStyle(Color.black)
                .background(Color.white)
            )
            renderer.scale = 2
            return renderer.uiImage
        }
        images = rendered
        sharing = !rendered.isEmpty
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [UIImage]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items.map { $0 as Any }, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
