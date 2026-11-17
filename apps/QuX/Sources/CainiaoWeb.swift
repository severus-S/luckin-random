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
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(AuthDiagnosticsHandler(owner: self), name: "quxDiagnostics")
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
        document.addEventListener('input', function(e) {
            var target = e.target;
            if (target && target.tagName === 'INPUT') {
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
        verificationTask?.cancel()
        verificationTask = nil
        let attempt = CainiaoLogin()
        loginAttempt = attempt
        showingLogin = true
        load(URLRequest(url: attempt.loginURL, timeoutInterval: 30))
    }

    private func load(_ request: URLRequest) {
        message = nil
        loading = true
        canSync = false
        activeNavigation = webView.load(request)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url else {
            decisionHandler(.allow)
            return
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        let writes = DispatchGroup()
        for cookie in cookies {
            writes.enter()
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                writes.leave()
            }
        }
        // Complete once, after every asynchronous Cookie write has finished.
        writes.notify(queue: .main) { decisionHandler(.allow) }
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
        showNavigationError(error, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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
