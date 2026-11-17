import Foundation
import SwiftUI
import WebKit

struct CainiaoPage: Identifiable {
    let title: String
    let url: URL
    var canSync = false
    var id: URL { url }

    static let parcels = Self(title: "菜鸟 · 我的快递",
                              url: URL(string: "https://page.cainiao.com/guoguo/app-myexpress-taobao/")!,
                              canSync: true)
    static let identity = Self(title: "菜鸟身份码",
                               url: URL(string: "https://page.cainiao.com/cn-app-web/identity-code/index.html#/")!)
    static let pending = Self(title: "待取包裹",
                              url: URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1100333/last-mile-fe/m-end-school-tab/home")!)
    static let account = Self(title: "菜鸟账号",
                              url: URL(string: "https://page.cainiao.com/cn-app-web/profile/index.html")!)

    static func detail(mailNo: String, carrierCode: String = "", orderCode: String = "") -> Self {
        var components = URLComponents(url: parcels.url.appendingPathComponent("express-detail.html"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "mailNo", value: mailNo),
            URLQueryItem(name: "cpCode", value: carrierCode),
            URLQueryItem(name: "orderCode", value: orderCode)
        ]
        return Self(title: "物流详情", url: components.url!)
    }

    static func allows(_ url: URL) -> Bool {
        LoginNavigation.allows(url)
    }
}

@MainActor
final class CainiaoBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var loading = true
    @Published var canGoBack = false
    @Published var canSync = false
    @Published var message: String?
    @Published var showingLogin = false
    @Published var diagnostics: [String] = []

    private let page: CainiaoPage
    private var activeNavigation: WKNavigation?
    private var loginAttempt: CainiaoLogin?
    private var verificationTask: Task<Void, Never>?
    private var latestMainURL: URL?
    private var warmupRequest: URLRequest?
    private var didWarmup = false
    private var requestSequence = 0
    private static var cleanupTask: Task<Void, Never>?

    init(page: CainiaoPage) {
        self.page = page
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            configuration.limitsNavigationsToAppBoundDomains = false
        }
        configuration.userContentController.addUserScript(WKUserScript(source: Self.inputCompatibilityScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: AuthDiagnostics.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: ParcelRequestBridge.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: SSODebug.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(AuthDiagnosticsHandler(owner: self), name: "quxDiagnostics")
        configuration.userContentController.add(SSODebugHandler(owner: self), name: "ssoDebug")
        configuration.userContentController.addScriptMessageHandler(ParcelBridgeHandler(owner: self), contentWorld: .page, name: "quxParcels")
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        reload()
    }

    static let inputCompatibilityScript = #"""
    (function() {
        if (window.location.host.indexOf('login') === -1) return;
        document.addEventListener('input', function(e) {
            var target = e.target;
            if (!target || target.tagName !== 'INPUT') return;
            var identity = (target.id || '') + ' ' + (target.name || '');
            var isCode = target.autocomplete === 'one-time-code' ||
                /sms.?code|check.?code|verify.?code|verification.?code|otp/i.test(identity) ||
                (target.maxLength === 4 && /^(tel|number|text)$/.test(target.type) &&
                 !/phone|mobile|password|account/i.test(identity));
            if (isCode) {
                target.dispatchEvent(new Event('change', { bubbles: true }));
                target.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: target.value }));
            }
        }, true);
    })();
    """#

    fileprivate func recordDiagnostic(_ message: WKScriptMessage) {
        guard let url = message.frameInfo.request.url, LoginNavigation.allows(url),
              let host = url.host?.lowercased(),
              let line = AuthDiagnostics.line(host: host, mainFrame: message.frameInfo.isMainFrame, body: message.body) else { return }
        diagnostics.append(line)
        if diagnostics.count > 80 { diagnostics.removeFirst(diagnostics.count - 80) }
    }

    private func appendNativeTrace(_ line: String) {
        diagnostics.append(line)
        if diagnostics.count > 80 { diagnostics.removeFirst(diagnostics.count - 80) }
    }

    fileprivate func requestParcelPage(_ scriptMessage: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        guard scriptMessage.frameInfo.isMainFrame,
              let url = scriptMessage.frameInfo.request.url,
              url.scheme == "https", url.host == CainiaoPage.parcels.url.host, url.path == CainiaoPage.parcels.url.path,
              let body = scriptMessage.body as? [String: Any], let pageNumber = body["page"] as? Int,
              (1...200).contains(pageNumber), let gateway = body["gateway"] as? String,
              ParcelSyncPolicy.gatewayHosts.contains(gateway) else {
            reply(nil, "Invalid parcel bridge request")
            return
        }
        Task { @MainActor in
            do {
                let response = try await fetchNativePage(pageNumber, gateway: gateway)
                // Do not report native/schema failures as successful empty data.
                _ = try ParcelSyncPolicy.page(response, expectedPage: pageNumber)
                if isParcelPage {
                    showingLogin = false
                    message = nil
                    canSync = true
                }
                reply(response, nil)
            } catch {
                let code = (error as? CainiaoSession.Failure)?.code ?? "FAIL_NATIVE_PARCEL_REQUEST"
                appendNativeTrace("Native parcels · " + code)
                if isParcelPage {
                    message = "包裹接口未成功（\(code)），网页空白不代表无包裹；本机数据已保留。可手动重新登录。"
                    canSync = true
                }
                reply(["ret": [code], "data": [:]], nil)
            }
        }
    }

    private func fetchNativePage(_ pageNumber: Int, gateway: String) async throws -> [String: Any] {
        guard ParcelSyncPolicy.gatewayHosts.contains(gateway),
              let endpoint = URL(string: "https://\(gateway)/h5/mtop.cainiao.lpc.packageservice.querytaobaopackagelist/1.0/") else {
            throw CainiaoSyncError.unavailable
        }
        let payload = "{\"appName\":\"MYEXPRESS\",\"needTemporality\":\"false\",\"currentPage\":\"\(pageNumber)\",\"pageSize\":\"5\"}"
        return try await CainiaoSession.request(endpoint: endpoint, payload: payload,
            store: webView.configuration.websiteDataStore.httpCookieStore,
            trace: { [weak self] line in self?.appendNativeTrace(line) })
    }

    func reload() {
        verificationTask?.cancel()
        verificationTask = nil
        loginAttempt = nil
        showingLogin = false
        load(URLRequest(url: page.url, timeoutInterval: 30))
    }

    func login() {
        verificationTask?.cancel()
        verificationTask = nil
        let attempt = CainiaoLogin()
        loginAttempt = attempt
        showingLogin = true
        load(URLRequest(url: attempt.loginURL, timeoutInterval: 30))
    }

    // One-time upgrade migration: the previous version overwrote same-name
    // Cainiao tokens, so provenance cannot be recovered. Reset only that set.
    private func prepareCookies() async {
        if Self.cleanupTask == nil {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            Self.cleanupTask = Task { @MainActor in
                let key = "qux.cookie-domain-cleanup.v1"
                guard !UserDefaults.standard.bool(forKey: key) else { return }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.getAllCookies { cookies in
                        let group = DispatchGroup()
                        let legacy = cookies.filter(CookieCompatibility.shouldRemoveLegacyCopy)
                        print("[SSO-Debug] cleanup legacy Cainiao cookies count=\(legacy.count)")
                        for cookie in legacy {
                            group.enter()
                            store.delete(cookie) { group.leave() }
                        }
                        group.notify(queue: .main) {
                            UserDefaults.standard.set(true, forKey: key)
                            continuation.resume()
                        }
                    }
                }
            }
        }
        await Self.cleanupTask?.value
    }

    private func load(_ request: URLRequest) {
        message = nil
        loading = true
        canSync = false
        requestSequence += 1
        let sequence = requestSequence
        Task { @MainActor in
            await prepareCookies()
            guard sequence == requestSequence else { return }
            if !didWarmup {
                didWarmup = true
                warmupRequest = request
                print("[SSO-Debug] first-party warmup https://h5api.m.taobao.com/")
                activeNavigation = webView.load(URLRequest(url: URL(string: "https://h5api.m.taobao.com/")!, timeoutInterval: 5))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if sequence == requestSequence { finishWarmup() }
                }
            } else {
                warmupRequest = nil
                activeNavigation = webView.load(request)
            }
        }
    }

    private func finishWarmup() {
        guard let request = warmupRequest else { return }
        warmupRequest = nil
        webView.stopLoading()
        print("[SSO-Debug] warmup finished; loading original request")
        activeNavigation = webView.load(request)
    }

    fileprivate func recordSSODebug(_ message: WKScriptMessage) {
        guard let url = message.frameInfo.request.url, LoginNavigation.allows(url),
              let data = message.body as? [String: Any], let type = data["type"] as? String,
              ["ready", "hook", "replace", "assign", "mtop-error"].contains(type) else { return }
        // Full URL/stack logging is explicitly requested for local Xcode debugging.
        print("[SSO-Debug] [MainFrame: \(message.frameInfo.isMainFrame)] \(data)")
        // The copyable in-app report keeps query values and call stacks out.
        var line = "SSO · \(url.host ?? "") · \(type)"
        if let code = data["code"] as? String,
           code.range(of: "^FAIL_[A-Z0-9_]{1,100}$", options: .regularExpression) != nil { line += " · " + code }
        if let installed = data["installed"] as? Bool { line += " · installed=\(installed)" }
        diagnostics.append(line)
        if diagnostics.count > 80 { diagnostics.removeFirst(diagnostics.count - 80) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let frame = action.targetFrame?.isMainFrame
        print("[SSO-Debug] navigationAction [MainFrame: \(frame.map(String.init) ?? "new-window")] \(action.request.url?.absoluteString ?? "nil")")
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if !NetworkAccessPolicy.isWebKitURL(url) {
            decisionHandler(.cancel)
            // WKWebView cannot load native-app schemes itself. Cancel only its
            // unsupported navigation, then hand the exact URL to the OS.
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                print("[SSO-Debug] external scheme=\(url.scheme ?? "") opened=\(opened)")
                if !opened {
                    Task { @MainActor [weak self] in
                        self?.message = "系统未找到可处理 \(url.scheme ?? "此") 链接的应用，网页可继续使用。"
                    }
                }
            }
            return
        }
        // HTTP/HTTPS login and SSO transitions are owned by the website.
        // No Cookie check, return-page cancellation or login-domain block here.
        if let url = action.request.url {
            if LoginNavigation.isLogin(url) { showingLogin = true }
            if action.targetFrame?.isMainFrame == true { latestMainURL = url }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        print("[SSO-Debug] serverRedirect [MainFrame: true] \(webView.url?.absoluteString ?? "nil")")
        latestMainURL = webView.url
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
        message = nil
        loading = true
        canSync = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        message = nil
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        if warmupRequest != nil { finishWarmup(); return }
        loading = false
        message = nil
        canGoBack = webView.canGoBack
        canSync = isParcelPage
        if let attempt = loginAttempt, let url = webView.url, attempt.isReturn(url) {
            // SSO return has actually finished; do not run a background MTOP
            // account check while the website is still completing login.
            loginAttempt = nil
            reload()
            return
        }
        if loginAttempt == nil && webView.url?.host == page.url.host && webView.url?.path == page.url.path {
            showingLogin = false
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil || !(navigationAction.targetFrame!.isMainFrame) {
            message = nil
            loading = true
            canSync = false
            activeNavigation = webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        reload()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        self.message = String(message.prefix(180))
        completionHandler()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if warmupRequest != nil { finishWarmup(); return }
        showNavigationError(error, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if warmupRequest != nil { finishWarmup(); return }
        showNavigationError(error, navigation: navigation)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        canSync = false
        message = "网页已停止，请重新打开。"
    }

    private func showNavigationError(_ error: Error, navigation: WKNavigation?) {
        guard navigation === activeNavigation,
              let message = NavigationFailure.message(for: error) else { return }
        loading = false
        canSync = false
        canGoBack = webView.canGoBack
        self.message = message
    }

    func verifySession() {
        guard verificationTask == nil,
              let currentURL = webView.url,
              ParcelSyncPolicy.isBusinessPage(currentURL) else { return }
        verificationTask = Task { @MainActor in
            defer { verificationTask = nil }
            do {
                try await CainiaoSession.verify(
                    store: webView.configuration.websiteDataStore.httpCookieStore)
                guard !Task.isCancelled, webView.url == currentURL else { return }
                message = "菜鸟业务会话校验通过。"
            } catch {
                guard !Task.isCancelled, webView.url == currentURL,
                      webView.url.map(ParcelSyncPolicy.isBusinessPage) == true else { return }
                let code = (error as? CainiaoSession.Failure)?.code
                    ?? "NETWORK_\((error as NSError).code)"
                message = "菜鸟校验未通过（\(code)）。已保留当前网页。"
            }
        }
    }

    private var isParcelPage: Bool {
        let expected = CainiaoPage.parcels.url
        return page.canSync && webView.url?.host == expected.host && webView.url?.path == expected.path
            && webView.url.map(CainiaoPage.allows) == true
    }

    func readParcels() async throws -> [Parcel] {
        guard isParcelPage else { throw CainiaoSyncError.unavailable }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let context = try await webView.callAsyncJavaScript(Self.pageContextScript, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
        guard isParcelPage else { throw CainiaoSyncError.unavailable }
        let ready = ParcelSyncPolicy.hasSyncCookie(cookies) && context["home"] as? Bool == true
        print("[SSO-Debug] sync native; pageReady=\(ready); empty=\(context["empty"] as? Bool == true)")
        if ready {
            showingLogin = false
        }
        // This request never invokes lib.login or changes WebView location.
        let host = context["gateway"] as? String ?? "acs.m.taobao.com"
        guard ParcelSyncPolicy.gatewayHosts.contains(host) else { throw CainiaoSyncError.unavailable }
        var parcels: [String: Parcel] = [:]
        for pageNumber in 1...200 {
            try Task.checkCancellation()
            guard isParcelPage else { throw CainiaoSyncError.unavailable }
            let response = try await fetchNativePage(pageNumber, gateway: host)
            try Task.checkCancellation()
            guard isParcelPage else { throw CainiaoSyncError.unavailable }
            let result = try ParcelSyncPolicy.page(response, expectedPage: pageNumber)
            for parcel in result.parcels { parcels[parcel.id] = parcel }
            if result.isLast {
                return parcels.values.sorted {
                    let left = $0.updatedAt ?? .distantPast, right = $1.updatedAt ?? .distantPast
                    return left == right ? $0.id < $1.id : left > right
                }
            }
        }
        throw CainiaoSyncError.pagination
    }

    static let pageContextScript = #"""
    const text = document.body ? document.body.innerText : "";
    const empty = text.includes("最近好像没有什么包裹");
    const home = empty || text.includes("我的快递") || text.includes("查快递");
    const config = window.lib && window.lib.mtop && window.lib.mtop.config || {};
    const gateway = [config.prefix || "acs", config.subDomain || "m", config.mainDomain || "taobao.com"].join(".");
    return {home, empty, gateway};
    """#

}

@MainActor
private final class AuthDiagnosticsHandler: NSObject, WKScriptMessageHandler {
    weak var owner: CainiaoBrowser?
    init(owner: CainiaoBrowser) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.recordDiagnostic(message)
    }
}

@MainActor
private final class SSODebugHandler: NSObject, WKScriptMessageHandler {
    weak var owner: CainiaoBrowser?
    init(owner: CainiaoBrowser) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.recordSSODebug(message)
    }
}

@MainActor
private final class ParcelBridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: CainiaoBrowser?
    init(owner: CainiaoBrowser) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let owner else { replyHandler(nil, "Browser closed"); return }
        owner.requestParcelPage(message, reply: replyHandler)
    }
}
