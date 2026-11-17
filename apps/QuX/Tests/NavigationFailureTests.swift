import XCTest
@testable import QuXCore

final class NavigationFailureTests: XCTestCase {
    func testIntentionalNavigationInterruptionsDoNotShowNetworkFailure() {
        XCTAssertNil(NavigationFailure.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertNil(NavigationFailure.message(for: NSError(domain: "WebKitErrorDomain", code: 102)))
    }

    func testRealNetworkAndCertificateFailuresRemainVisible() {
        for code in [NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
                     NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted] {
            let message = NavigationFailure.message(for: NSError(domain: NSURLErrorDomain, code: code))
            XCTAssertNotNil(message)
            XCTAssertTrue(message?.contains(String(code)) == true)
        }
    }

    func testCancellationCodeInAnotherDomainIsNotHidden() {
        XCTAssertNotNil(NavigationFailure.message(for: NSError(domain: "OtherDomain", code: NSURLErrorCancelled)))
        XCTAssertNotNil(NavigationFailure.message(for: NSError(domain: NSURLErrorDomain, code: 102)))
    }

    func testErrorMessageDoesNotExposeSessionOrQueryData() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [
            NSLocalizedDescriptionKey: "secret session",
            NSURLErrorFailingURLErrorKey: URL(string: "https://login.m.taobao.com/?token=secret")!
        ])
        let message = NavigationFailure.message(for: error)!
        XCTAssertFalse(message.contains("secret"))
        XCTAssertFalse(message.contains("token"))
    }
}
