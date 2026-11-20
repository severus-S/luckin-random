import SwiftUI
import WebKit

@MainActor final class LoginBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let view: WKWebView
    @Published var error = ""
    @Published var loading = true
    @Published var ready = false
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let script = """
        (()=>{
          if(location.origin!=='https://wx.zhinengxiyifang.cn'||location.pathname!=='/static/washer-h5/commonWasher/latest/index.html')return;
          const send=kind=>window.webkit.messageHandlers.washLogin.postMessage({kind});
          const allowed=new Set(['/login','/__uwash__']);let attempts=0;
          const install=()=>{
            const root=document.getElementById('app');const vm=root&&root.__vue__;
            if(!vm||!vm.$router){if(++attempts<150)setTimeout(install,100);else send('notReady');return;}
            const router=vm.$router;if(router.__washGuard)return;router.__washGuard=true;
            router.beforeEach((to,from,next)=>{
              if(['/','/home','/migrate'].includes(to.path)){next({path:'/__uwash__',replace:true});return;}
              if(!allowed.has(to.path)){send('blocked');next(false);return;}
              next();
            });
            router.afterEach(to=>{if(to.path==='/__uwash__')send('returned');});
            send('ready');
          };install();
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self
        configuration.userContentController.add(WeakLoginHandler(self), name: "washLogin")
        view.load(URLRequest(url: LaundryProtocol.loginURL))
    }
    func readToken() async throws -> String {
        guard ready, let url = view.url, LaundryProtocol.isLoginDocument(url) else { throw LaundryError(message: "请在 U净官方网页登录后，再点击完成登录。") }
        let value = try await view.evaluateJavaScript("window.localStorage.getItem('token') || ''")
        guard let token = value as? String, !token.isEmpty else { throw LaundryError(message: "尚未读取到登录结果，请先在网页完成手机号登录。") }
        return token
    }
    func reload() { error = ""; loading = true; ready = false; view.load(URLRequest(url: LaundryProtocol.loginURL)) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "wx.zhinengxiyifang.cn", let url = message.frameInfo.request.url, LaundryProtocol.isLoginDocument(url), let body = message.body as? [String: String] else { return }
        switch body["kind"] {
        case "ready": ready = true; loading = false
        case "returned": error = "网页登录已返回，请点击右上角“完成登录”验证会话。"
        case "blocked": error = "请完成登录后返回净洗，选择程序和付款将在支付宝进行。"
        case "notReady": loading = false; error = "官方登录组件未准备好，请重载页面。"
        default: break
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { loading = false; self.error = "官方登录页面加载失败，请检查网络后重载。" }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel); return }
        if LaundryProtocol.isLoginDocument(url) { decisionHandler(.allow); return }
        if url.scheme == "https", url.host == "wx.zhinengxiyifang.cn", ["/about_us/privacy_policy.html", "/about_us/user_agreement.html"].contains(url.path) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        error = "此跳转不属于登录页面，请在官方登录页完成登录后返回。"
    }
}

private final class WeakLoginHandler: NSObject, WKScriptMessageHandler {
    weak var owner: LoginBrowser?
    init(_ owner: LoginBrowser) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}

struct LoginWeb: UIViewRepresentable {
    let browser: LoginBrowser
    func makeUIView(context: Context) -> WKWebView { browser.view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
