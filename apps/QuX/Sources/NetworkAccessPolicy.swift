import Foundation

enum NetworkAccessPolicy {
    // Everything WebKit can load remains in the WebView. Other schemes are
    // handed to iOS without a host whitelist or canOpenURL query requirement.
    static func isWebKitURL(_ url: URL) -> Bool {
        ["http", "https", "about", "data", "blob", "file", "javascript"].contains(url.scheme?.lowercased() ?? "")
    }

    static func redirectedRequest(_ proposed: URLRequest, from previousURL: URL?) -> URLRequest {
        var request = proposed
        let next = proposed.url
        func port(_ url: URL?) -> Int? { url?.port ?? (url?.scheme == "https" ? 443 : url?.scheme == "http" ? 80 : nil) }
        if next?.host != previousURL?.host || next?.scheme != previousURL?.scheme || port(next) != port(previousURL) {
            // Follow the redirect, but never carry manually attached credentials
            // into a different origin. WebKit still owns its own Cookie store.
            request.setValue(nil, forHTTPHeaderField: "Cookie")
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
