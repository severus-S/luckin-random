import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: AutoJob?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(store.data.configuration.emergencyStop ? "紧急停止已开启" : "任务调度可运行", systemImage: store.data.configuration.emergencyStop ? "pause.circle.fill" : "clock")
                    Text("由服务端执行，默认 Asia/Shanghai。手机不需要保持后台运行；未接入远程推送时，需要主动打开 App 查看付款通知。").font(.footnote).foregroundStyle(.secondary)
                    Button("立即停止全部任务", role: .destructive) { store.perform { try await store.stop() } }
                }
                if !store.data.useBackend { ContentUnavailableView("自动任务需要在线后端", systemImage: "server.rack", description: Text("先在设置中连接持续运行的 HTTPS 服务。离线模式不承诺后台定时下单。")) }
                ForEach(store.jobs) { j in Button { editing = j } label: { VStack(alignment: .leading, spacing: 6) { Text(String(format: "%02d:%02d", j.hour, j.minute)).font(.title2.monospacedDigit()); Text("\(j.enabled ? "启用" : "暂停") · \(j.timezone)"); Text(j.shop.name).font(.footnote); Text("最多 \(money(j.maxCents)) · 周日=0：\(j.weekdays.map(String.init).joined(separator: ","))").font(.caption) }.foregroundStyle(.primary) } }
                if store.data.useBackend { Section { Button("新建自动任务", systemImage: "plus") { guard let shop = store.data.configuration.shop else { store.message = "请先选择门店"; return }; editing = AutoJob(poolId: store.pool.id, shop: shop, maxCents: store.data.configuration.limits.cup) } } }
                Section("执行记录") { ForEach(store.runs) { r in VStack(alignment: .leading, spacing: 4) { Text(r.slot); Text(store.data.orders.first(where: { $0.id == r.intentId })?.stateName ?? "已触发，请查通知箱或订单记录").font(.caption).foregroundStyle(.secondary) } }; if store.runs.isEmpty { Text("暂无执行记录").foregroundStyle(.secondary) } }
            }.navigationTitle("自动任务").toolbar { Button("刷新", systemImage: "arrow.clockwise") { store.perform { try await store.refreshJobs(); try await store.refreshHistory() } } }.task { store.perform { try await store.refreshJobs() } }
                .sheet(item: $editing) { j in NavigationStack { JobEditor(job: j).environmentObject(store) } }
        }
    }
}
struct JobEditor: View {
    @EnvironmentObject var store: AppStore; @Environment(\.dismiss) var dismiss
    @State var job: AutoJob; @State private var saving = false
    var body: some View {
        Form {
            Section {
                Toggle("启用任务", isOn: $job.enabled)
                Picker("咖啡池", selection: $job.poolId) { ForEach(store.data.configuration.pools) { Text($0.name).tag($0.id) } }
                Text("门店：\(job.shop.name)")
                Button("改用当前常用门店") { if let shop = store.data.configuration.shop { job.shop = shop } }
                Stepper("小时 \(job.hour)", value: $job.hour, in: 0...23)
                Stepper("分钟 \(job.minute)", value: $job.minute, in: 0...59)
                TextField("IANA 时区", text: $job.timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
                CentField(title: "本任务单杯上限", cents: $job.maxCents)
            }
            Section("重复日期") {
                ForEach(0..<7, id: \.self) { n in Toggle(["周日","周一","周二","周三","周四","周五","周六"][n], isOn: Binding(get: { job.weekdays.contains(n) }, set: { on in if on { if !job.weekdays.contains(n) { job.weekdays.append(n) } } else { job.weekdays.removeAll { $0 == n } } })) }
            }
            Section {
                Toggle("我授权在上述日期、门店和限额内自动创建订单", isOn: $job.authorized)
                Text("任务授权独立于全局真实下单授权。首次默认关闭；任一紧急停止或预算限制都会阻止下单。定时任务不补执行错过的时段。").font(.footnote).foregroundStyle(.secondary)
                Button(saving ? "保存中" : "保存到服务端") { saving = true; store.perform { defer { saving = false }; try await store.saveJob(job); dismiss() } }.disabled(saving || (job.enabled && !job.authorized))
            }
        }.navigationTitle("任务配置").toolbar { Button("取消") { dismiss() } }
    }
}
