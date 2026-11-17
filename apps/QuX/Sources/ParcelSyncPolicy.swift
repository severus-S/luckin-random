import Foundation

enum ParcelSyncPolicy {
    static let gatewayHosts = ["acs.m.taobao.com", "h5api.m.taobao.com", "acs.m.cainiao.com", "cn-acs.m.cainiao.com"]
    static func allowedGateway(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
        gatewayHosts.contains(url.host ?? "") && url.path.range(of: "^/h5/[a-z0-9.]+/1\\.0/$", options: .regularExpression) != nil
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
        cookies.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let path = url.path
            return (url.host == domain || ($0.domain.hasPrefix(".") && url.host?.hasSuffix("." + domain) == true)) &&
                (path == $0.path || (path.hasPrefix($0.path) && ($0.path.hasSuffix("/") || path.dropFirst($0.path.count).hasPrefix("/")))) &&
                (!$0.isSecure || url.scheme == "https") && ($0.expiresDate == nil || $0.expiresDate! > now)
        }.sorted { $0.path.count > $1.path.count }
    }
    static func blocksLoginReturn(_ url: URL, mainFrame: Bool, passedQuickEnter: Bool,
                                  manualLogin: Bool, cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        guard mainFrame, !manualLogin, ["login.m.taobao.com", "login.taobao.com"].contains(url.host ?? "") else { return false }
        let hasTaobaoLogin = cookies.contains {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (domain == "taobao.com" || domain.hasSuffix(".taobao.com")) &&
                ["cookie2", "unb"].contains($0.name) && !$0.value.isEmpty && ($0.expiresDate == nil || $0.expiresDate! > now)
        }
        return passedQuickEnter || hasTaobaoLogin
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
