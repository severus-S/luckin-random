// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UWashCore", platforms: [.macOS(.v13)], products: [.library(name: "UWashCore", targets: ["UWashCore"])], targets: [
    .target(name: "UWashCore", path: "Sources", exclude: ["ContentView.swift", "App.swift", "LaundryAPI.swift", "LaundrySession.swift", "QRScanner.swift", "PaymentWeb.swift"], sources: ["LaundryCore.swift"]),
    .testTarget(name: "UWashCoreTests", dependencies: ["UWashCore"], path: "Tests")
])
