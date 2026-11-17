// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuX",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(name: "QuXCore", path: "Sources",
                exclude: ["App.swift", "CainiaoWeb.swift", "ContentView.swift", "GlassStyle.swift", "CainiaoSession.swift"],
                sources: ["Parcel.swift", "LoginNavigation.swift", "NavigationFailure.swift", "CainiaoLogin.swift", "AuthDiagnostics.swift", "CookieCompatibility.swift", "SSODebug.swift", "ParcelSyncPolicy.swift", "NetworkAccessPolicy.swift", "ParcelRequestBridge.swift"]),
        .testTarget(name: "QuXTests", dependencies: ["QuXCore"], path: "Tests")
    ]
)
