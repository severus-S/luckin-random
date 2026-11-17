import Foundation

struct CainiaoLogin {
    let state: String
    init(state: String = UUID().uuidString) { self.state = state }

    var returnURL: URL {
        var parts = URLComponents(string: "https://page.cainiao.com/cn-app-web/profile/index.html")!
        parts.queryItems = [URLQueryItem(name: "qux_auth_complete", value: "1"), URLQueryItem(name: "auth_state", value: state)]
        return parts.url!
    }

    var loginURL: URL {
        var parts = URLComponents(string: "https://cnlogin.cainiao.com/login")!
        parts.queryItems = [URLQueryItem(name: "cnSite", value: "CAINIAO2C"),
                            URLQueryItem(name: "isMobile", value: "true"),
                            URLQueryItem(name: "lang", value: "zh_CN"),
                            URLQueryItem(name: "redirectURL", value: returnURL.absoluteString)]
        return parts.url!
    }

    func isReturn(_ url: URL) -> Bool {
        guard LoginNavigation.allows(url), url.host == returnURL.host, url.path == returnURL.path else { return false }
        return value("auth_state", in: url) == state && value("qux_auth_complete", in: url) == "1"
    }

    static func isSSO(_ url: URL) -> Bool {
        LoginNavigation.allows(url) && url.host == "cnlogin.cainiao.com" && url.path == "/doSsoLogin"
    }

    func ownsSSO(_ url: URL) -> Bool {
        guard Self.isSSO(url), value("redirectURL", in: url) == returnURL.absoluteString,
              value("cnSite", in: url) == "CAINIAO2C",
              value("stSite", in: url) == "78", let ticket = value("st", in: url) else { return false }
        return (16...8192).contains(ticket.count) && !ticket.contains("\n") && !ticket.contains("\r")
    }

    static func hasBusinessSession(_ result: [String: Any]) -> Bool {
        guard let codes = result["ret"] as? [String], codes.contains(where: { $0 == "SUCCESS" || $0.hasPrefix("SUCCESS::") }),
              let data = result["data"] as? [String: Any],
              let page = data["data"] as? [String: Any], let header = page["header"] as? [String: Any],
              let content = header["data"] as? [String: Any], let account = content["data"] as? [String: Any],
              let nick = account["nick"] as? String else { return false }
        return !nick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !nick.contains("请登录")
    }

    private func value(_ key: String, in url: URL) -> String? {
        let matches = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == key } ?? []
        return matches.count == 1 ? matches[0].value : nil
    }
}
