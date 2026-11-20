import Foundation

final class LaundryAPI: NSObject, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // API redirects must never forward the bearer credential to another origin.
        completionHandler(nil)
    }
    func call(_ path: String, method: String = "GET", query: [String: String] = [:], body: JSON? = nil, token: String = "") async throws -> JSON {
        let request = try LaundryProtocol.request(path: path, method: method, query: query, body: body, token: token)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LaundryError(message: "没有收到有效网络响应。") }
        return try LaundryProtocol.unwrap(data, status: response.statusCode)
    }
}
