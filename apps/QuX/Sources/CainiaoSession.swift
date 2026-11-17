import Foundation
import CryptoKit
import WebKit

// Mirrors the APK's read-only MtopClient / AccountProfile check. Credentials
// remain in WKHTTPCookieStore; no token or response is logged or persisted here.
@MainActor
enum CainiaoSession {
    enum Failure: Error {
        case rejected(String)
        var code: String { switch self { case let .rejected(code): return code } }
    }

    static func verify(store: WKHTTPCookieStore) async throws {
        let endpoint = URL(string: "https://cn-acs.m.cainiao.com/h5/mtop.cainiao.app.e2e.engine.page.fetch.cn/1.0/")!
        let result = try await request(endpoint: endpoint, payload: "{\"pageId\":1800,\"h5Version\":\"2\"}", store: store)
        guard CainiaoLogin.hasBusinessSession(result) else { throw Failure.rejected(CainiaoLogin.diagnosticCode(result)) }
    }

    static func request(endpoint: URL, payload: String, store: WKHTTPCookieStore) async throws -> [String: Any] {
        guard ParcelSyncPolicy.allowedGateway(endpoint) else { throw Failure.rejected("INVALID_GATEWAY") }
        let api = endpoint.path.components(separatedBy: "/").filter { !$0.isEmpty }[1]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: FollowSessionRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let allCookies = await store.allCookies()
            let cookies = ParcelSyncPolicy.cookies(allCookies, for: endpoint)
            let tokenCookie = cookies.first { $0.name == "_m_h5_tk" }
            let token = CainiaoLogin.signingToken(tokenCookie?.value)
            let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            let signature = Insecure.MD5.hash(data: Data("\(token)&\(timestamp)&12574478&\(payload)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            parts.queryItems = ["jsv": "2.7.0", "appKey": "12574478", "t": timestamp, "sign": signature,
                "api": api, "v": "1.0",
                "type": "originaljson", "dataType": "json", "data": payload].map { URLQueryItem(name: $0.key, value: $0.value) }
            if endpoint.host?.hasSuffix(".cainiao.com") == true {
                parts.queryItems?.append(URLQueryItem(name: "accountSite", value: "cainiao2c"))
            }
            // URLComponents leaves '+' unescaped; form-style servers decode it as space.
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            var request = URLRequest(url: parts.url!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("https://page.cainiao.com", forHTTPHeaderField: "Origin")
            request.setValue("https://page.cainiao.com/", forHTTPHeaderField: "Referer")
            request.setValue("cainiao_c_user", forHTTPHeaderField: "x-biz-type")
            request.setValue("env=cainiao_c_user", forHTTPHeaderField: "x-biz-info")
            request.setValue("zh_CN", forHTTPHeaderField: "cn_account_lang")
            request.setValue("QuX/0.8.13 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue(ParcelSyncPolicy.cookieHeader(cookies), forHTTPHeaderField: "Cookie")
            let source = tokenCookie.map { "domain=\($0.domain),path=\($0.path)" } ?? "undefined (no matching _m_h5_tk)"
            print("[MTOP-Debug] endpoint=\(endpoint.absoluteString) api=\(api) attempt=\(attempt + 1)")
            print("[MTOP-Debug] Cookie keys=\(cookies.map(\.name).sorted()) tokenSource=\(source)")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.rejected("INVALID_HTTP_RESPONSE") }
            guard http.statusCode == 200 else { throw Failure.rejected("HTTP_\(http.statusCode)") }
            guard data.count < 2_000_000 else { throw Failure.rejected("RESPONSE_TOO_LARGE") }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: endpoint) {
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard endpoint.host == domain || endpoint.host?.hasSuffix("." + domain) == true else { continue }
                await store.save(cookie)
            }
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.rejected("INVALID_RESPONSE") }
            if (result["ret"] as? [String] ?? []).contains(where: { $0 == "SUCCESS" || $0.hasPrefix("SUCCESS::") }) { return result }
            let code = CainiaoLogin.diagnosticCode(result)
            print("[MTOP-Debug] endpoint=\(endpoint.absoluteString) ret=\(code) tokenSource=\(source)")
            if attempt == 0 && CainiaoLogin.shouldRetryToken(code) { continue }
            throw Failure.rejected(code)
        }
        throw Failure.rejected("TOKEN_RETRY_EXHAUSTED")
    }
}

private final class FollowSessionRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        print("[MTOP-Debug] following HTTP redirect status=\(response.statusCode) host=\(request.url?.host ?? "")")
        completionHandler(NetworkAccessPolicy.redirectedRequest(request, from: response.url))
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in getAllCookies { continuation.resume(returning: $0) } }
    }
    func save(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            setCookie(cookie) { continuation.resume() }
        }
    }
}
