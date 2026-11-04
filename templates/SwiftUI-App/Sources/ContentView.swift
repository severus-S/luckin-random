import SwiftUI

struct ContentView: View {
    @AppStorage("welcomeCount") private var count = 0
    @AppStorage("savedNote") private var note = ""
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("欢迎使用 __APP_NAME__", systemImage: "hand.wave.fill")
                        .font(.title2)
                    Text("SwiftUI 原生应用 · 数据保存在本机")
                        .foregroundStyle(.secondary)
                }
                Section("互动") {
                    Text("已点击 \(count) 次")
                        .accessibilityIdentifier("tapCount")
                    Button("点击 +1", systemImage: "plus.circle") { count += 1 }
                }
                Section("持久化便签") {
                    TextField("输入内容，关闭后仍会保留", text: $note, axis: .vertical)
                        .accessibilityLabel("持久化便签")
                    Text("使用同一签名身份和 Bundle ID 覆盖更新后，检查此处数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("版本", value: version)
                }
            }
            .navigationTitle("__APP_NAME__")
        }
    }
}
