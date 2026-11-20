// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HairCore", platforms: [.macOS(.v13)], targets: [
    .target(name: "HairCore", path: "Sources", exclude: ["App.swift", "ContentView.swift", "HairSession.swift", "LoginWeb.swift", "QRScanner.swift"], sources: ["HairCore.swift"]),
    .testTarget(name: "HairCoreTests", dependencies: ["HairCore"], path: "Tests")
])
