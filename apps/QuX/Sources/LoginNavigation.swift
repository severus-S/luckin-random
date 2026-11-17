import Foundation

enum LoginNavigation {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["cainiao.com", "taobao.com", "tmall.com", "alipay.com", "alibaba.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    // Preserve the server's path/query while upgrading legacy web redirects.
    // Only unwrap the documented Taobao H5 carrier; never open an external app.
    static func webFallback(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "http",
           var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
           parts.port == nil || parts.port == 80 {
            parts.scheme = "https"
            parts.port = nil
            if let secure = parts.url, allows(secure) { return secure }
        }
        guard url.scheme?.lowercased() == "tbopen", url.host == "m.taobao.com",
              url.path == "/tbopen/index.html", url.user == nil, url.password == nil, url.port == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let targets = (parts.queryItems ?? []).filter { $0.name == "h5Url" }
        guard targets.count == 1, let value = targets.first?.value,
              let destination = URL(string: value) else { return nil }
        if allows(destination) { return destination }
        // Do not recursively unwrap app schemes or arbitrary nested redirects.
        if destination.scheme?.lowercased() == "http" { return webFallback(destination) }
        return nil
    }

    static func blockedMessage(_ url: URL?) -> String {
        guard let url else { return "无法识别网页跳转，请重试。" }
        // Deliberately omit paths, credentials, query strings and fragments.
        let scheme = String((url.scheme ?? "unknown").prefix(24))
        let host = String((url.host ?? "无域名").prefix(100))
        return "无法继续此跳转（\(scheme) · \(host)）。请将此提示反馈。"
    }

    static func isLogin(_ url: URL) -> Bool {
        guard allows(url), let host = url.host?.lowercased() else { return false }
        return ["login.m.taobao.com", "login.taobao.com", "cnlogin.cainiao.com"].contains(host)
            && ["/login.htm", "/login", "/mini_login.htm", "/havanaone/login/login.htm"].contains(url.path)
    }

    // Widget login returns through an iframe message page. A top-level login needs
    // the actual destination, so cookies and redirects complete in the same WebView.
    static func topLevelLogin(_ url: URL, returningTo destination: URL) -> URL? {
        guard isLogin(url), allows(destination),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let redirectKeys = ["redirecturl", "redirect_url", "returnurl", "return_url", "redirecttype", "ttid", "tpl_redirect_url", "hidecallapp"]
        var items = (components.queryItems ?? []).filter { !redirectKeys.contains($0.name.lowercased()) }
        items.append(URLQueryItem(name: "redirectURL", value: destination.absoluteString))
        items.append(URLQueryItem(name: "hideCallApp", value: "true"))
        components.queryItems = items
        return components.url
    }

    static func loginURL(returningTo destination: URL) -> URL {
        topLevelLogin(URL(string: "https://login.m.taobao.com/login.htm")!, returningTo: destination)!
    }
}
