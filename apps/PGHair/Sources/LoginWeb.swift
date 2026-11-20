import SwiftUI
import WebKit

@MainActor final class HairLogin: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let view: WKWebView
    @Published var error = ""
    @Published var loading = true
    override init() {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        let paths = String(data: try! JSONEncoder().encode(HairPolicy.loginPaths.sorted()), encoding: .utf8)!
        let code = """
        (()=>{
          const allowed=new Set(\(paths));let count=0;
          const send=(kind)=>window.webkit.messageHandlers.hairLogin.postMessage({kind});
          const attempt=()=>{
            const root=document.querySelector('.myApp')||document.querySelector('#app');
            const vm=root&&root.__vue__;
            if(!vm||!vm.$router||!window.getApp){if(++count<150)setTimeout(attempt,100);return;}
            const router=vm.$router;
            if(router.__hairGuard)return;router.__hairGuard=true;
            window.setCache('redirectRoute','/__pghair__');
            router.beforeEach((to,from,next)=>{
              if(to.path==='/'){next({path:'/__pghair__',replace:true});return;}
              if(!allowed.has(to.path)){send('blocked');next(false);return;}
              next();
            });
            router.afterEach((to)=>{if(to.path==='/__pghair__')send('loginReturned');});
            send('ready');
          };attempt();
        })();
        """
        c.userContentController.addUserScript(WKUserScript(source: code, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        view = WKWebView(frame: .zero, configuration: c)
        super.init()
        view.navigationDelegate = self
        // Weak proxy prevents the content controller retaining this owner indefinitely.
        c.userContentController.add(WeakHairHandler(self), name: "hairLogin")
        let rules = """
        [{"trigger":{"url-filter":".*","if-domain":["*cnzz.com","*mmstat.com","*pangolin-sdk-toutiao.com","*pglstatp-toutiao.com"]},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "PGHairLoginResources1", encodedContentRuleList: rules) { [weak self] list, _ in
            guard let self else { return }
            if let list { self.view.configuration.userContentController.add(list) }
            self.view.load(URLRequest(url: HairPolicy.loginURL))
        }
    }
    func readToken() async throws -> String {
        guard let url = view.url, url.scheme == "https", url.host == "h5.qiekj.com", HairPolicy.loginPaths.contains(url.path) else { throw HairError(message: "请返回官方登录页完成登录。") }
        let value = try await view.evaluateJavaScript("window.getApp && getApp().globalData.User.getToken() || ''")
        guard let value = value as? String, !value.isEmpty else { throw HairError(message: "尚未读取到登录结果，请先在网页中完成登录。") }
        return value
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "h5.qiekj.com", let data = message.body as? [String: String] else { return }
        if data["kind"] == "ready" { loading = false }
        if data["kind"] == "blocked" { error = "该入口不属于吹风机精简版，请完成登录后返回。" }
        if data["kind"] == "loginReturned" { error = "网页登录已返回，请点击右上角“完成登录”验证账号。" }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { loading = false; self.error = "官方登录页面加载失败，请检查网络后重载。" }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel); return }
        if url.scheme == "https", url.host == "h5.qiekj.com", HairPolicy.loginPaths.contains(url.path) { decisionHandler(.allow) }
        else if url.scheme == "https", url.host == "h5.qiekj.com", url.path == "/" {
            decisionHandler(.cancel)
            view.load(URLRequest(url: URL(string: "https://h5.qiekj.com/__pghair__?disabledQiYu=1")!))
        } else { decisionHandler(.cancel); error = "登录页面要求外部跳转，本版暂不能完成这条路径。" }
    }
}

private final class WeakHairHandler: NSObject, WKScriptMessageHandler {
    weak var owner: HairLogin?
    init(_ owner: HairLogin) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}

struct HairLoginWeb: UIViewRepresentable {
    let browser: HairLogin
    func makeUIView(context: Context) -> WKWebView { browser.view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
