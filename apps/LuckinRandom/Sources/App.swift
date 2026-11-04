import SwiftUI

@main
struct LuckinRandomApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        if Task.isCancelled { break }
                        if scenePhase == .active && store.data.useBackend && !store.busy {
                            try? await store.refreshHistory()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && store.data.useBackend {
                        store.perform { try await store.refreshHistory() }
                    }
                }
                .onContinueUserActivity("com.sjx13.luckin.random") { _ in Task { await store.buy() } }
        }
    }
}
