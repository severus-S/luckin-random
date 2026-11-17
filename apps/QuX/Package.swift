// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuX",
    platforms: [.macOS(.v13), .iOS(.v17)],
    targets: [
        .target(name: "QuXCore", path: "Sources",
                exclude: ["App.swift", "CainiaoWeb.swift", "ContentView.swift", "GlassStyle.swift"],
                sources: ["Parcel.swift", "LoginNavigation.swift", "NavigationFailure.swift", "LoginCompletion.swift"]),
        .testTarget(name: "QuXTests", dependencies: ["QuXCore"], path: "Tests")
    ]
)
