import AppIntents

struct RandomCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "随机买一杯瑞幸"
    static var description = IntentDescription("打开 Luckin Random，按已保存咖啡池与消费限制随机点单。默认模拟，真实下单需在设置中明确授权。")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        let store = AppStore.shared
        store.selectedTab = 0
        await store.buy()
        return .result()
    }
}
struct CoffeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RandomCoffeeIntent(), phrases: ["用\(.applicationName)随机买一杯", "在\(.applicationName)随机选咖啡"], shortTitle: "随机买一杯瑞幸", systemImageName: "shuffle")
    }
}
