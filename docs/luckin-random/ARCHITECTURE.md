# Luckin Random 技术架构

更新：2026-11-05。执行前先读 PROGRESS.md；当前真实接口受令牌 401 阻塞，未云端编译。

## 组成与选择

SwiftUI 原生 App → 自有单用户 HTTPS REST 服务 → 瑞幸官方 Streamable HTTP MCP。
客户端本地保存咖啡池；需要定时任务时显式同步配置到服务端。Node.js 22.14+ / TypeScript / SQLite，无外部数据库和付费依赖。
Windows 不运行 Xcode；复用根 `.github/workflows/build-ios.yml` 和 `scripts/ci_build.py`。

SQLite 使用 Node 内置 node:sqlite，当前本机 Node 22.14.0 会提示实验性 API。上线前固定并验证 Node 版本，不能承诺其跨大版本兼容。单实例、单用户、单进程；不得把此版本作为多租户服务横向扩容。

客户端离线模拟无需部署即可操作咖啡池、预览、模拟支付、历史和备份。后端 MockGateway 用于领域测试；独立 Mock MCP 服务用于真正的 HTTP/JSON-RPC/SSE 协议测试。两者都不访问真实账号。

## 状态和防重复

一次触发以持久化 UUID 标识，服务端同 key 不再创建第二个订单；不同请求内容复用 key 返回冲突。

`validating → previewed` 是只读路径。

`validating → creating → awaitingPayment → paid/preparing/ready/completed` 是创建路径。
创建前先写入 SQLite 预留；创建超时或解析失败进入 `unknown`。服务重启将遗留 `creating` 变为 `unknown`，绝不自动重发。
有官方订单 ID 时只读查询恢复；无 ID 时当前公开文档没有按本地幂等 key 查单的能力，必须在官方渠道人工核对。系统保持阻断，没有自动“解锁继续买”按钮。

服务端互斥处理同一实例的触发；待支付、创建中或未知结果阻止新的真实触发。已支付、未支付与未知金额均计入周期预算；仅官方确认取消或确定未创建才释放。取消超时同样记 unknown。
普通配置同步不改变服务端停止/授权标志；显式授权端点才可恢复任务或开启真实下单。真实消费限额另存授权快照；配置中提高金额不会扩大该快照，需再次明确授权。
App 在 POST 前保存 pendingIntent 和后端地址；网络异常只查询订单列表，不自动重发 POST。若服务端始终找不到 key，保持待确认，需进一步人工核对。

## 随机、规格、金额

默认密码学随机源等概率；权重启用后按正数权重抽取。禁用候选排除；多候选时优先排除上次成功创建的商品；仅剩一个可用候选时允许重复。
每轮每款最多尝试一次。详情 → 按官方属性 ID 逐项 switch → 核对选中结果 → preview；保存的 SKU 不能替代实时校验。
门店、SKU、数量和商品必须与预览结果一致。预算只接受官方 preview.discountPrice，转换为整数分；客户端传入价格不参与信任。
优惠券只把 preview.couponCodeList 原样传入创建，不宣称自行最优选券。
同一轮在创建前重新检查全局停止、用户授权、消费上限、门店以及任务是否被暂停或更改。

## 持久化和迁移

客户端 Application Support/state-v1.json：LocalData.version、Configuration.schemaVersion、咖啡池、历史、待确认 key。原子写入、iOS 文件保护；坏文件保留，不静默覆盖；恢复备份关闭真实下单、开启紧急停止。
当前只存在 v1；将来的 v2 必须编写显式转换并补旧备份测试，不能直接更改既有字段类型。未知版本拒绝加载。
服务端 migrations/001_initial.sql 建立配置、加密 secrets、intent 状态快照、事件、任务、防重 slot、通知箱。启动按编号执行尚未应用的迁移，拒绝打开高于代码版本的数据库。

## 服务端调度

15 秒轮询，以任务 IANA 时区匹配日期/小时/分钟；默认 Asia/Shanghai，星期天=0。数据库 `(job_id,slot)` 唯一约束防止同一分钟重复，包括时钟回拨和服务重启。
不补执行离线时错过的时段。暂停、关闭、删除、紧急停止均可阻止创建；已经发出的创建请求只能核对状态，不能假设紧急停止撤回了请求。
默认任务关闭，独立 authorized=true 才能启用；还受全局真实授权、服务端 allowLive、contractVerified 和预算限制。
通知可靠落库，当前只在 App 打开时读取，不具备锁屏远程推送。正式无人值守体验仍需要通知通道验收。
服务端每 15 秒对最多 20 笔有官方 ID 的活动订单做只读状态更新；手机在前台每 15 秒读取订单与通知箱。未变化状态不重复记事件；不以轮询方式重发创建或取消。

## 支付与扩展边界

仅显示官方 HTTPS payOrderQrCodeUrl，限制官方域名，付款码和取餐号分开。未验证 payOrderUrl 的 iOS 支付能力，客户端不展示或转换它；不生成钱包私有参数。
仅在官方已支付状态展示 takeMealCodeInfo.code，未知或“生成中”不展示为有效取餐号；不把 takeOrderId 擅自编码成取餐二维码。
App Intents 打开 App 后执行正常路径，受同一幂等/授权控制。WidgetKit、主屏幕快速操作、APNs 留为未实现，不添加未经验证的后台技巧。
