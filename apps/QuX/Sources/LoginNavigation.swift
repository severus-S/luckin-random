import Foundation

enum LoginNavigation {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["cainiao.com", "taobao.com", "tmall.com", "alipay.com", "alibaba.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func isLogin(_ url: URL) -> Bool {
        guard allows(url), let host = url.host?.lowercased() else { return false }
        return ["login.m.taobao.com", "login.taobao.com", "cnlogin.cainiao.com"].contains(host)
            && ["/login.htm", "/login", "/mini_login.htm"].contains(url.path)
    }

    // Widget login returns through an iframe message page. A top-level login needs
    // the actual destination, so cookies and redirects complete in the same WebView.
    static func topLevelLogin(_ url: URL, returningTo destination: URL) -> URL? {
        guard isLogin(url), allows(destination),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let redirectKeys = ["redirecturl", "redirect_url", "returnurl", "return_url", "redirecttype", "ttid"]
        var items = (components.queryItems ?? []).filter { !redirectKeys.contains($0.name.lowercased()) }
        items.append(URLQueryItem(name: "redirectURL", value: destination.absoluteString))
        components.queryItems = items
        return components.url
    }

    static func loginURL(returningTo destination: URL) -> URL {
        topLevelLogin(URL(string: "https://login.m.taobao.com/login.htm")!, returningTo: destination)!
    }
}
