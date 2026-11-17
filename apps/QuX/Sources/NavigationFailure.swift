import Foundation

enum NavigationFailure {
    static func message(for error: Error) -> String? {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled { return nil }
        // A deliberately replaced or denied WebKit navigation can report this
        // legacy policy error after the next document has already started.
        if failure.domain == "WebKitErrorDomain" && failure.code == 102 { return nil }
        if failure.domain == NSURLErrorDomain {
            switch failure.code {
            case NSURLErrorTimedOut:
                return "网页连接超时（-1001），请重试。"
            case NSURLErrorNotConnectedToInternet:
                return "网络连接不可用（-1009），请连接网络后重试。"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "无法解析网页地址（\(failure.code)），请检查网络后重试。"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid:
                return "网页安全连接失败（\(failure.code)），请检查网络与系统时间。"
            default:
                return "网页连接失败（\(failure.code)），请重试。"
            }
        }
        return "网页载入失败（\(failure.domain) \(failure.code)），请重新打开网页。"
    }
}
