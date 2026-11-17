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
    private var hasPassedQuickEnter = false
    private var loopPreventCount = 0
    private var quickEnterPassedAt: Date?
    private var latestMainURL: URL?
    private var warmupRequest: URLRequest?
    private var didWarmup = false
    private var requestSequence = 0
    private static var cleanupTask: Task<Void, Never>?
    private var cookieJobs: [() -> Void] = []
    private var cookieJobRunning = false

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
        configuration.userContentController.addUserScript(WKUserScript(source: SSODebug.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(AuthDiagnosticsHandler(owner: self), name: "quxDiagnostics")
        configuration.userContentController.add(SSODebugHandler(owner: self), name: "ssoDebug")
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

    func reload() {
        verificationTask?.cancel()
        verificationTask = nil
        loginAttempt = nil
        showingLogin = false
        load(URLRequest(url: page.url, timeoutInterval: 30))
    }

    func login() {
        hasPassedQuickEnter = false
        quickEnterPassedAt = nil
        loopPreventCount = 0
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
        guard let scheme = action.request.url?.scheme?.lowercased(),
              ["http", "https", "about"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }
        if let url = action.request.url, let fallback = LoginNavigation.webFallback(url),
           action.targetFrame?.isMainFrame != false {
            decisionHandler(.cancel)
            var request = action.request
            request.url = fallback
            load(request)
            return
        }
        guard let url = action.request.url,
              CainiaoPage.allows(url) || url.absoluteString == "about:blank" else {
            if action.targetFrame?.isMainFrame != false {
                loading = false
                message = LoginNavigation.blockedMessage(action.request.url)
            }
            decisionHandler(.cancel)
            return
        }
        if CookieCompatibility.isQuickEnterHandoff(url, source: action.sourceFrame.request.url ?? latestMainURL) {
            hasPassedQuickEnter = true
            quickEnterPassedAt = Date()
        }
        if CainiaoLogin.isSSO(url), let attempt = loginAttempt, !attempt.ownsSSO(url) {
            loading = false
            message = "登录交接与本次请求不匹配，请从菜单重新登录。"
            decisionHandler(.cancel)
            return
        }
        if let attempt = loginAttempt, action.targetFrame?.isMainFrame == true, attempt.isReturn(url) {
            // The SSO response has set its cookies. Do not render the profile SPA:
            // its unrelated auto-login can race our read-only session check.
            decisionHandler(.cancel)
            verifySession(attempt: attempt)
            return
        }
        if LoginNavigation.isLogin(url) {
            // Business pages can require their own Taobao login. Keep the parent,
            // target frame and return address even when no Cainiao attempt exists.
            showingLogin = true
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [self] cookies in
            if hasPassedQuickEnter, CookieCompatibility.inLoopWindow(passedAt: quickEnterPassedAt),
               url.host == "login.m.taobao.com", CookieCompatibility.hasTaobaoSession(cookies) {
                if action.targetFrame?.isMainFrame == false {
                    print("[SSO-Debug] allowing iframe refresh \(url.absoluteString)")
                } else if action.targetFrame?.isMainFrame == true && loopPreventCount < 1 {
                    loopPreventCount += 1
                    print("[SSO-Debug] cancelled first main-frame SSO loop \(url.absoluteString)")
                    loading = false
                    message = "已阻止一次登录回跳；请查看登录诊断，或手动重新登录。"
                    decisionHandler(.cancel)
                    return
                }
            }
            if action.targetFrame?.isMainFrame == true { latestMainURL = url }
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        var responseCookies: [HTTPCookie] = []
        if let response = navigationResponse.response as? HTTPURLResponse, let url = response.url {
            var headers: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            responseCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        }
        synchronizeCookies(in: webView.configuration.websiteDataStore.httpCookieStore,
                           responseCookies: responseCookies) {
            decisionHandler(.allow)
        }
    }

    private func synchronizeCookies(in store: WKHTTPCookieStore, responseCookies: [HTTPCookie] = [],
                                    completion: @escaping () -> Void) {
        cookieJobs.append { [self] in
            let group = DispatchGroup()
            // Only response-owned cookies, with original domain/path/properties.
            for cookie in responseCookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [self] in
                completion()
                cookieJobRunning = false
                runNextCookieJob()
            }
        }
        runNextCookieJob()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        print("[SSO-Debug] serverRedirect [MainFrame: true] \(webView.url?.absoluteString ?? "nil")")
        if let url = webView.url {
            if CookieCompatibility.isQuickEnterHandoff(url, source: latestMainURL) {
                hasPassedQuickEnter = true
                quickEnterPassedAt = Date()
            }
            latestMainURL = url
        }
    }

    private func runNextCookieJob() {
        guard !cookieJobRunning, !cookieJobs.isEmpty else { return }
        cookieJobRunning = true
        let job = cookieJobs.removeFirst()
        job()
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
            verifySession(attempt: attempt)
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

    private func verifySession(attempt: CainiaoLogin) {
        guard verificationTask == nil else { return }
        loading = true
        canSync = false
        message = "正在校验菜鸟业务会话…"
        verificationTask = Task { @MainActor in
            do {
                try await CainiaoSession.verify(store: webView.configuration.websiteDataStore.httpCookieStore)
                guard !Task.isCancelled, loginAttempt?.state == attempt.state else { return }
                verificationTask = nil
                reload()
            } catch {
                guard !Task.isCancelled, loginAttempt?.state == attempt.state else { return }
                verificationTask = nil
                loading = false
                let code = (error as? CainiaoSession.Failure)?.code ?? "NETWORK_\((error as NSError).code)"
                message = "菜鸟校验未通过（\(code)）。可返回业务网页继续登录；请反馈此错误码。"
            }
        }
    }

    private var isParcelPage: Bool {
        let expected = CainiaoPage.parcels.url
        return page.canSync && webView.url?.host == expected.host && webView.url?.path == expected.path
            && webView.url.map(CainiaoPage.allows) == true
    }

    func readParcels() async throws -> [Parcel] {
        var parcels: [String: Parcel] = [:]
        for pageNumber in 1...200 {
            try Task.checkCancellation()
            guard isParcelPage else { throw CainiaoSyncError.login }
            let response = try await webView.callAsyncJavaScript(
                Self.readPageScript, arguments: ["page": pageNumber], in: nil, contentWorld: .page
            )
            try Task.checkCancellation()
            guard isParcelPage else { throw CainiaoSyncError.login }
            let page = try CainiaoParcelPage(response, expectedPage: pageNumber)
            for parcel in page.parcels {
                parcels[parcel.id] = parcel
            }
            if page.isLast {
                return parcels.values.sorted {
                    let left = $0.updatedAt ?? .distantPast
                    let right = $1.updatedAt ?? .distantPast
                    return left == right ? $0.id < $1.id : left > right
                }
            }
        }
        throw CainiaoSyncError.pagination
    }

    // Use the same read-only list operation and parameters as the loaded official page.
    static let readPageScript = #"""
    if (location.protocol !== "https:" || location.host !== "page.cainiao.com" ||
        !/^\/guoguo\/app-myexpress-taobao\/?$/.test(location.pathname)) {
        return { error: "login" };
    }
    const sdk = window.lib && window.lib.mtop;
    if (!sdk || typeof sdk.request !== "function") return { error: "unavailable" };
    let timer;
    try {
        sdk.config.prefix = "acs";
        sdk.config.subDomain = "m";
        const response = await Promise.race([
            sdk.request({
                api: "mtop.cainiao.lpc.packageservice.querytaobaopackagelist",
                v: "1.0", dataType: "json", H5Request: true, AntiCreep: true,
                LoginRequest: true, sessionOption: "AutoLoginAndManualLogin",
                data: { appName: "MYEXPRESS", needTemporality: "false", currentPage: String(page), pageSize: "5" }
            }),
            new Promise((_, reject) => { timer = setTimeout(() => reject({}), 15000); })
        ]);
        const data = response && response.data;
        if (!data || !Array.isArray(data.packages)) return { error: "schema" };
        const text = v => typeof v === "string" ? v : Number.isSafeInteger(v) ? String(v) : "";
        const fields = ["packageId", "mailNo", "partnerName", "cpCode", "partnerCode", "orderCode",
            "logisticsStatus", "logisticsStatusDesc", "lastLogisticDetail",
            "logisticsGmtModified", "signedDate", "consignDate"];
        return {
            current: text(data.currentPage), total: text(data.totalPage),
            rows: data.packages.map(row => {
                if (!row || typeof row !== "object") return null;
                const item = (row.packageItem || [])[0] || {};
                const station = row.packageStation || {};
                const record = Object.fromEntries(fields.map(key => [key, text(row[key])]));
                record.title = text(item.customeItemTitle || item.itemTitle || item.itemName || item.title);
                record.station = text(station.stationName);
                record.stationID = text(station.stationId);
                record.pickupCode = record.logisticsStatus === "AGENT_SIGN" &&
                    (station.showAuthCode === true || station.showAuthCode === "true") ? text(station.authCode) : "";
                return record;
            })
        };
    } catch (error) {
        const status = Array.isArray(error && error.ret) ? error.ret.join(" ") : "";
        return { error: /SESSION|NEED_LOGIN|LOGIN_REQUIRED|TOKEN_EXPIRED/i.test(status) ? "login" : "unavailable" };
    } finally {
        clearTimeout(timer);
    }
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
