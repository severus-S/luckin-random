import Foundation
import Security

struct HTTPFailure: LocalizedError {
    var status: Int; var message: String
    var errorDescription: String? { message }
}

enum Keychain {
    static func get(_ name: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sjx13.ios.luckinrandom", kSecAttrAccount as String: name, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func set(_ name: String, _ value: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sjx13.ios.luckinrandom", kSecAttrAccount as String: name]
        SecItemDelete(q as CFDictionary)
        if value.isEmpty { return }
        var insert = q; insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw AppFailure("无法保存配对密钥到钥匙串") }
    }
}
private struct APIErrorBody: Decodable { let message: String }

struct API {
    let base: String
    func request<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        guard let root = URL(string: base), root.scheme == "https", root.host != nil, root.user == nil, root.password == nil, root.query == nil, root.fragment == nil,
              let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw AppFailure("请设置有效的 HTTPS 后端地址") }
        let key = Keychain.get("backendKey")
        guard !key.isEmpty else { throw AppFailure("请先在设置中保存后端配对密钥") }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 90
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = body
        // No automatic retry, no cookies and no disk cache. Redirects never carry credentials.
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("服务器响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPFailure(status: http.statusCode, message: (try? JSONDecoder().decode(APIErrorBody.self, from: data).message) ?? "服务请求失败（\(http.statusCode)）")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, _ body: B) async throws -> T { try await request(method, path, body: JSONEncoder().encode(body)) }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
