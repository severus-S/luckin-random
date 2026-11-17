import Foundation

enum CookieCompatibility {
    static func shouldRemoveLegacyCopy(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "cainiao.com" &&
            ["cookie2", "unb", "_tb_token_", "sgcookie", "t", "_m_h5_tk", "_m_h5_tk_enc"].contains(cookie.name)
    }
    static func hasTaobaoSession(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        let valid = cookies.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "taobao.com" && !$0.value.isEmpty && ($0.expiresDate == nil || $0.expiresDate! > now)
        }
        return ["cookie2", "unb"].allSatisfy { name in valid.contains { $0.name == name } }
    }
    static func isQuickEnterHandoff(_ url: URL, source: URL?) -> Bool {
        guard LoginNavigation.allows(url) else { return false }
        let raw = url.absoluteString.lowercased()
        return ["mini_apply_st", "vst", "havana_iv_token"].contains(where: raw.contains) ||
            (source?.host == "login.m.taobao.com" &&
             (url.host == "cainiao.com" || url.host?.hasSuffix(".cainiao.com") == true))
    }
    static func inLoopWindow(passedAt: Date?, now: Date = Date()) -> Bool {
        guard let passedAt else { return false }
        return (0...5).contains(now.timeIntervalSince(passedAt))
    }
}
