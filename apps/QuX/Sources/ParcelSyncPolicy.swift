import Foundation

enum ParcelSyncPolicy {
    static let gatewayHosts = ["acs.m.taobao.com", "h5api.m.taobao.com", "acs.m.cainiao.com", "cn-acs.m.cainiao.com"]
    static func allowedGateway(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
        gatewayHosts.contains(url.host ?? "") && url.path.range(of: "^/h5/[a-z0-9.]+/1\\.0/?$", options: .regularExpression) != nil
    }
    static func hasSyncCookie(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        cookies.contains {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let trusted = ["taobao.com", "cainiao.com"].contains { domain == $0 || domain.hasSuffix("." + $0) }
            return trusted && ["cookie2", "unb", "_m_h5_tk", "cna"].contains($0.name) && !$0.value.isEmpty &&
                ($0.expiresDate == nil || $0.expiresDate! > now)
        }
    }
    static func cookies(_ cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> [HTTPCookie] {
        let matching = cookies.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let path = url.path
            return (url.host == domain || ($0.domain.hasPrefix(".") && url.host?.hasSuffix("." + domain) == true)) &&
                (path == $0.path || (path.hasPrefix($0.path) && ($0.path.hasSuffix("/") || path.dropFirst($0.path.count).hasPrefix("/")))) &&
                (!$0.isSecure || url.scheme == "https") && ($0.expiresDate == nil || $0.expiresDate! > now)
        }.sorted {
            if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
            let leftDomain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let rightDomain = $1.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if leftDomain.count != rightDomain.count { return leftDomain.count > rightDomain.count }
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.value < $1.value
        }
        var seen = Set<String>()
        // One winner per name. This exact array supplies BOTH the header and sign.
        return matching.filter { seen.insert($0.name).inserted }
    }
    static func cookieHeader(_ cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    static func isBusinessPage(_ url: URL) -> Bool {
        guard LoginNavigation.allows(url), let host = url.host,
              host == "cainiao.com" || host.hasSuffix(".cainiao.com"),
              !host.contains("login"), !host.contains("passport") else { return false }
        let path = url.path.lowercased()
        return !path.contains("login") && !path.contains("passport") && path != "/dossoLogin".lowercased()
    }

    static func page(_ result: [String: Any], expectedPage: Int) throws -> CainiaoParcelPage {
        guard let data = result["data"] as? [String: Any], let packages = data["packages"] as? [[String: Any]] else { throw CainiaoSyncError.schema }
        func text(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
        let fields = ["packageId", "mailNo", "partnerName", "cpCode", "partnerCode", "orderCode", "logisticsStatus", "logisticsStatusDesc", "lastLogisticDetail", "logisticsGmtModified", "signedDate", "consignDate"]
        let rows: [[String: String]] = packages.map { row in
            var record = Dictionary(uniqueKeysWithValues: fields.map { ($0, text(row[$0])) })
            let item = (row["packageItem"] as? [[String: Any]])?.first ?? [:]
            let station = row["packageStation"] as? [String: Any] ?? [:]
            record["title"] = text(item["customeItemTitle"] ?? item["itemTitle"] ?? item["itemName"] ?? item["title"])
            record["station"] = text(station["stationName"])
            record["stationID"] = text(station["stationId"])
            let visible = station["showAuthCode"] as? Bool == true || station["showAuthCode"] as? String == "true"
            record["pickupCode"] = record["logisticsStatus"] == "AGENT_SIGN" && visible ? text(station["authCode"]) : ""
            return record
        }
        return try CainiaoParcelPage(["current": text(data["currentPage"]), "total": text(data["totalPage"]), "rows": rows], expectedPage: expectedPage)
    }
}
