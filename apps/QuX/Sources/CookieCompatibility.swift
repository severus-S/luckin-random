import Foundation

enum CookieCompatibility {
    static func cainiaoClone(_ cookie: HTTPCookie) -> HTTPCookie? {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard domain == "taobao.com" || domain.hasSuffix(".taobao.com"),
              var properties = cookie.properties else { return nil }
        properties[.domain] = ".cainiao.com"
        return HTTPCookie(properties: properties)
    }

    // Response cookies win over an older store snapshot with the same identity.
    static func writes(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        var originals: [String: HTTPCookie] = [:]
        var clones: [String: HTTPCookie] = [:]
        func key(_ cookie: HTTPCookie) -> String { "\(cookie.domain)|\(cookie.path)|\(cookie.name)" }
        for cookie in cookies {
            originals[key(cookie)] = cookie
            if let clone = cainiaoClone(cookie) { clones[key(clone)] = clone }
        }
        for (key, clone) in clones { originals[key] = clone }
        return Array(originals.values)
    }
}
