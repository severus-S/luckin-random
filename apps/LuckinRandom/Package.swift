// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LuckinCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LuckinCore", targets: ["LuckinCore"])],
    targets: [
        .target(name: "LuckinCore", path: "Sources", exclude: ["App.swift", "API.swift", "AppStore.swift", "ContentView.swift", "OrderViews.swift", "SettingsViews.swift", "TaskViews.swift", "Shortcuts.swift"], sources: ["Models.swift"]),
        .testTarget(name: "LuckinCoreTests", dependencies: ["LuckinCore"], path: "Tests")
    ]
)
