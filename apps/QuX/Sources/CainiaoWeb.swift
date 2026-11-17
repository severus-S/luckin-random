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
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else {
            return false
        }
        return ["cainiao.com", "taobao.com", "tmall.com", "alipay.com", "alibaba.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }
}

@MainActor
final class CainiaoBrowser: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var loading = true
    @Published var canGoBack = false
    @Published var canSync = false
    @Published var message: String?

    private let page: CainiaoPage

    init(page: CainiaoPage) {
        self.page = page
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        reload()
    }

    func reload() {
        message = nil
        webView.load(URLRequest(url: page.url, timeoutInterval: 30))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url,
              CainiaoPage.allows(url) || (url.absoluteString == "about:blank" && action.targetFrame?.isMainFrame == false) else {
            if action.targetFrame?.isMainFrame != false { message = "该网页要求打开外部应用或其他站点。" }
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame == nil {
            decisionHandler(.cancel)
            webView.load(action.request)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        canSync = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        canGoBack = webView.canGoBack
        canSync = isParcelPage
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        showNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        canSync = false
        message = "网页已停止，请重新打开。"
    }

    private func showNavigationError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        canSync = false
        message = "网页暂时无法载入，请检查网络后重试。"
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
