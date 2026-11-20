import SwiftUI
import WebKit

@MainActor final class LoginBrowser: ObservableObject {
    let view: WKWebView
    @Published var error = ""
    @Published var ready = false
    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        view = WKWebView(frame: .zero, configuration: configuration)
        // An unmatched route mounts the official API client without opening a business page or OAuth.
        view.load(URLRequest(url: URL(string: "https://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html#/__uwash_auth_helper")!))
    }
    func sendCode(mobile: String) async throws {
        guard mobile.count == 11, mobile.hasPrefix("1"), mobile.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw LaundryError(message: "请输入 11 位手机号。") }
        guard let u = view.url, u.scheme == "https", u.host == "wx.zhinengxiyifang.cn", u.path.hasPrefix("/static/washer-h5/commonWasher/") else { throw LaundryError(message: "请先完成官方 U净网页登录，再读取登录结果。") }
        // Reuse the official nonce/timestamp/HMAC SMS implementation; no extracted key is shipped.
        let value = try await view.callAsyncJavaScript("const vm = document.getElementById('app').__vue__; if (!vm || !vm.$http) throw new Error('NOT_READY'); const response = await vm.$http.getCode({mobile, type: 1}); return response && response.code === 0;", arguments: ["mobile": mobile], in: nil, contentWorld: .page)
        guard value as? Bool == true else { throw LaundryError(message: "验证码请求未完成，请稍后重试。") }
    }
}

struct LoginWeb: UIViewRepresentable {
    let browser: LoginBrowser
    func makeCoordinator() -> Coordinator { Coordinator(browser: browser) }
    func makeUIView(context: Context) -> WKWebView { browser.view.navigationDelegate = context.coordinator; return browser.view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let browser: LoginBrowser
        init(browser: LoginBrowser) { self.browser = browser }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Boolean(document.getElementById('app') && document.getElementById('app').__vue__ && document.getElementById('app').__vue__.$http && document.getElementById('app').__vue__.$http.getCode)") { value, _ in
                self.browser.ready = value as? Bool == true
                if !self.browser.ready { self.browser.error = "官方验证码组件未准备好，请重新加载。" }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { browser.error = "登录网页加载失败，请检查网络后重载。" }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = navigationAction.request.url else { decisionHandler(.cancel); return }
            if u.scheme == "https", ["zhinengxiyifang.cn", "ujing.online"].contains(where: { u.host == $0 || u.host?.hasSuffix("." + $0) == true }) { decisionHandler(.allow) }
            else if u.absoluteString == "about:blank" { decisionHandler(.allow) }
            else { decisionHandler(.cancel); browser.error = "登录网页要求外部服务。本版暂无法完成这条登录路径。" }
        }
    }
}

struct PaymentWeb: UIViewRepresentable {
    let url: URL
    let failure: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(failure: failure) }
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: c)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let failure: (String) -> Void
        init(failure: @escaping (String) -> Void) { self.failure = failure }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let value = navigationAction.request.url else { decisionHandler(.cancel); return }
            if value.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard let url = LaundryProtocol.paymentURL(value.absoluteString) else { decisionHandler(.cancel); failure("支付页面要求打开尚未支持的地址，请在官方 U净核对该订单。"); return }
            if url.scheme == "https" { decisionHandler(.allow) }
            else { decisionHandler(.cancel); UIApplication.shared.open(url) { opened in if !opened { self.failure("无法打开支付 App，请检查是否已安装。") } } }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, LaundryProtocol.paymentURL(url.absoluteString) != nil { webView.load(navigationAction.request) }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failure("支付网页加载失败。返回后请先刷新订单，避免重复支付。") }
    }
}
