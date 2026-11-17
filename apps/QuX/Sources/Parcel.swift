import Foundation

enum ParcelGroup: String, CaseIterable, Identifiable {
    case pickup = "待取件"
    case transit = "在途中"
    case signed = "已签收"

    var id: Self { self }
}

struct Parcel: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let mailNo: String
    let carrier: String
    let carrierCode: String
    let orderCode: String
    let status: String
    let statusText: String
    let description: String
    let station: String
    let stationID: String
    let pickupCode: String
    let updatedAt: Date?

    var group: ParcelGroup {
        switch status {
        case "AGENT_SIGN": .pickup
        case "SIGN": .signed
        default: .transit
        }
    }

    var stationGroup: String {
        if !stationID.isEmpty && stationID != "0" { return "id:\(stationID)" }
        if !station.isEmpty { return "name:\(station)" }
        return "unknown"
    }

    var label: String { title.isEmpty ? (carrier.isEmpty ? "包裹" : carrier) : title }
    var displayStatus: String { statusText.isEmpty ? group.rawValue : statusText }

    func matches(_ term: String) -> Bool {
        term.isEmpty || [label, mailNo, carrier, station, pickupCode].contains {
            $0.localizedCaseInsensitiveContains(term)
        }
    }
}

struct PickupSection: Identifiable {
    let id: String
    let name: String
    let parcels: [Parcel]

    static func grouped(_ parcels: [Parcel]) -> [Self] {
        let groups = Dictionary(grouping: parcels, by: \.stationGroup)
        return groups.map { key, rows in
            Self(id: key, name: rows.first { !$0.station.isEmpty }?.station ?? "未知取件点", parcels: rows)
        }.sorted { left, right in
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }

    static func shareText(_ sections: [Self]) -> String {
        sections.map { section in
            let lines = section.parcels.map { parcel in
                [parcel.pickupCode, parcel.carrier, parcel.mailNo.isEmpty ? "" : "尾号 \(parcel.mailNo.suffix(4))"]
                    .filter { !$0.isEmpty }.joined(separator: "  ")
            }
            return ([section.name] + lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct ParcelSnapshot: Codable {
    let syncedAt: Date
    let parcels: [Parcel]
}

enum ParcelSnapshotFile {
    private static func location() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("QuXParcels.json")
    }

    static func read() throws -> ParcelSnapshot? {
        let url = try location()
        do {
            return try JSONDecoder().decode(ParcelSnapshot.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    static func save(_ snapshot: ParcelSnapshot) throws {
        var url = try location()
        #if os(iOS)
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func clear() throws {
        do {
            try FileManager.default.removeItem(at: location())
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

enum CainiaoSyncError: LocalizedError {
    case login, unavailable, schema, pagination

    var errorDescription: String? {
        switch self {
        case .login: "同步接口未确认会话，已保留当前网页；可从菜单手动重新登录。"
        case .unavailable: "菜鸟暂时无法返回包裹，请检查网页提示后重试。"
        case .schema: "菜鸟返回的数据不完整，已保留本机包裹。"
        case .pagination: "包裹分页未完整返回，已保留本机包裹。"
        }
    }
}

struct CainiaoParcelPage {
    let parcels: [Parcel]
    let isLast: Bool

    init(_ response: Any?, expectedPage: Int) throws {
        guard let result = response as? [String: Any] else { throw CainiaoSyncError.schema }
        switch result["error"] as? String {
        case "login": throw CainiaoSyncError.login
        case "unavailable": throw CainiaoSyncError.unavailable
        case "schema": throw CainiaoSyncError.schema
        default: break
        }
        guard let rows = result["rows"] as? [[String: String]],
              let current = (result["current"] as? String).flatMap(Int.init),
              let total = (result["total"] as? String).flatMap(Int.init),
              current == expectedPage, total <= 200,
              total >= current || (expectedPage == 1 && total == 0 && rows.isEmpty) else {
            throw CainiaoSyncError.pagination
        }
        guard !rows.isEmpty || (expectedPage == 1 && total <= 1) else {
            throw CainiaoSyncError.pagination
        }
        isLast = current >= total
        parcels = try rows.map { row in
            func value(_ key: String) -> String {
                (row[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let mailNo = value("mailNo")
            let id = value("packageId").isEmpty ? mailNo : value("packageId")
            let status = value("logisticsStatus")
            guard !id.isEmpty, !status.isEmpty else { throw CainiaoSyncError.schema }
            let time = ["logisticsGmtModified", "signedDate", "consignDate"]
                .compactMap { Double(value($0)) }.first { $0.isFinite && $0 > 0 }
            return Parcel(
                id: id, title: value("title"), mailNo: mailNo, carrier: value("partnerName"),
                carrierCode: value("cpCode").isEmpty ? value("partnerCode") : value("cpCode"),
                orderCode: value("orderCode"), status: status, statusText: value("logisticsStatusDesc"),
                description: value("lastLogisticDetail"), station: value("station"),
                stationID: value("stationID"), pickupCode: status == "AGENT_SIGN" ? value("pickupCode") : "",
                updatedAt: time.map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
            )
        }
    }
}
