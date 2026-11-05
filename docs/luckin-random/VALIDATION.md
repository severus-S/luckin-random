# 本轮验收记录

时间：2026-11-05（公开平台研究始于 2026-11-04）。

| 检查 | 命令/证据 | 结果 |
|---|---|---|
| TypeScript 编译及后端测试 | services/luckin-random: npm test | 27/27 通过；全部 Mock，无真实消费 |
| 独立 Mock MCP | 上述测试自动启动 loopback HTTP MCP | 初始化、session、SSE、schema、规格、预览/创建/查单/取消闭环通过 |
| 依赖审计 | npm audit --omit=dev --audit-level=low | 0 known vulnerabilities；不是未来安全保证 |
| 工作区回归 | python scripts/selftest.py | 4/4 通过 |
| Swift 语法 | tree-sitter-swift 解析 11 个 .swift 文件 | 0 语法错误；不是 Swift 类型检查或 Xcode 构建 |
| 工程生成 | python scripts/project.py LuckinRandom | 原生工程已生成；中文显示名和固定 ID/版本写入 |
| CI 静态检查 | .tools/actionlint/actionlint.exe .github/workflows/build-ios.yml | 通过 |
| Python 语法 | python -m compileall -q scripts | 通过 |
| 差异空白检查 | git diff --check 本轮已跟踪路径 | 通过，另有 Windows CRLF 规范化提示 |
| 官方 MCP | tools/list 实际请求 | HTTP 401；随后正式初始化发现命令也失败，没有实时 schema |
| macOS Swift 核心测试 | 成功运行 41875870306 | 6/6 通过 |
| Xcode/IPA | 成功运行 41875870306，Xcode 16.4 / iPhoneOS 18.5 | 原生编译和未签名 IPA 通过；本机哈希/结构核对通过 |
| 签名/安装/真机/支付 | 需要用户设备操作和明确消费授权 | 未验证 |

本机完整后端测试输出保存于被忽略的 `artifacts/luckin-random-validation/backend-tests.txt`。源码包不含运行数据或认证资料。

自动化覆盖：等概率/加权统计、禁用/避免重复、失效候选重抽、全部不可用、价格/周期预算、优惠失效、并发重复、幂等冲突、超时未知阻断、已知订单恢复、支付状态倒退保护、后台状态更新、取消确认/取餐号、时区与任务防重/重启防重、暂停期间不创建、加密持久化/重启恢复、官方 QR 域名校验、缺少预算字段拒绝、消费授权快照、401 脱敏、MCP 协议及完整 HTTP Mock 流程、API 认证/权限/跨站/限流。

## 2026-11-05 公共仓库构建

公共仓库：https://github.com/severus-S/luckin-random 。首次源码提交 30bdfe01dbfd4a5ba5940d8e4dbc6d890eb774b0，通过 push 自动触发运行 https://github.com/severus-S/luckin-random/actions/runs/41869588528 。
当前仍等待 GitHub 分配 runner。官方同期公告 Actions/Webhooks 故障，已采取缓解措施但状态可能延迟；在看到真实成功结果前，不声称已有 IPA。标准 macos-15 runner，无付费 larger runner，无认证资料。

## 2026-11-05 服务恢复后重新触发

用户询问进度时，原公共 push 运行 41869588528 仍 queued。GitHub 官方状态已改为 operational，公告仍处于 monitoring；取消旧运行并确认 cancelled 后，使用既有 build-ios.ps1 触发一次新运行。
新运行：https://github.com/severus-S/luckin-random/actions/runs/41871798205 ，源码 a486f37b2dbb5f9daae40736b39cd8e342100c4d，当前 queued、未分配 runner，无编译日志或 IPA。保持单个活动构建，不将排队记为编译成功。

## 2026-11-05 队列配置复核

针对用户提供的截图，读取实际工作流、GitHub 当前 runner 文档和本次运行 API：

- runs-on 为 macos-15，官方当前列为免费标准 M1/arm64 runner；没有 self-hosted 或自定义 runner 标签。
- 仓库为 public、未 archived/disabled；Actions enabled=true，allowed_actions=all。
- 本次 check run 无错误注释，pending_deployments 为空；本仓库仅一项活动构建，前两项已取消，未发现本仓库并发锁或部署审批等待。
- 当前 run 41871798205 仍 queued，runner_id/runner_name 为空，steps 为空；没有 Xcode 编译证据或 IPA。
- GitHub 官方已恢复 operational，相关事故仍 monitoring。未据此推断积压队列全部恢复。

结论：当前未发现无效标签、仓库禁用或审批导致的等待，保留当前任务等待合理；无法承诺等多久或必然编译成功。截图的 10–30 分钟只是经验值，官方未提供该排队时长保证。官方 limits 中的 24 小时队列限制列在 self-hosted 类别，不能直接套用为本 GitHub-hosted job 的成功或超时保证。

来源：https://docs.github.com/en/actions/reference/runners/github-hosted-runners 、https://docs.github.com/en/actions/reference/limits 。未改 runner 配置、未重复触发任务。

2026-11-05：运行 41871798205 最终失败，check-run 注释明确报告 hosted runner 多次领取失败及 macOS arm64 capacity constraints，steps 为空。标签与权限有效不代表资源可用；此前记录为当时状态，不作为成功保证。使用独立 codex/luckin-random-intel 分支测试官方免费标准 macos-15-intel，不改默认 main 的稳定配置，待真实构建验证后再决定合入。

2026-11-05 Intel 实测：运行 41875147576 成功分配免费标准 macos-15-intel，27 项后端测试和 6 项 Swift 核心测试通过；Xcode 16.4 / iPhoneOS SDK 18.5 已实际进入编译。AppStore 初始化中的局部 error 与 catch 隐式 error 冲突导致编译失败，已改名 loadFailure，等待真实复测。此失败是源码编译错误，区别于之前 ARM runner 分配失败。

## 2026-11-05 Intel 编译与产物核对

运行 41875870306，源码 33a85b36856bdd21e8f212c511ec7f152efe2ba8，macos-15-intel / Xcode 16.4 / iPhoneOS SDK 18.5。27 项后端测试、6 项 Swift 核心测试通过；build.log 存在 BUILD SUCCEEDED，plutil/lipo/otool、未签名检查、IPA 打包及上传步骤均通过。
下载的真实 IPA 为 LuckinRandom 0.1.0 (4)，Bundle ID com.sjx13.ios.luckinrandom，minimum iOS 17.0，arm64，显示名“瑞幸随机咖啡”。SHA256：e8c0dcb9885abef9cb417b4d4faf7b5efe27f10aa893de2a984a3c0e312763bd。
Windows 独立 ZIP CRC、plist、Mach-O、来源 commit/run ID、SHA256、无签名资源检查通过。未签名，未安装到手机。此刻 GitHub 总运行状态仍 in_progress，保留该事实；不把编译产物验证当作签名、安装、续签或支付成功。
经真实编译验证后，已将 Intel runner 和初始化修复合入 main（fda69b21cebe587564af0e4abef37399c8efcb54），自动触发 main 复测 41877911324，未重复手动触发。

## 2026-11-05 IPA 交付

已把真实编译产物整理到 artifacts/latest/LuckinRandom/LuckinRandom-unsigned.ipa，旁附 manifest.json、SHA256SUMS、安装说明和 delivery-audit.json。版本 0.1.0 (4)，SHA256 e8c0dcb9885abef9cb417b4d4faf7b5efe27f10aa893de2a984a3c0e312763bd。
交付前再次核对：唯一作业的所有步骤均已 completed，测试/编译/上传/Complete job 为 success；原始日志证实后端 27/27、Swift 6/6、BUILD SUCCEEDED；本机对真实 Payload/Info.plist/Mach-O/ZIP/哈希及来源 commit/run ID 全部核验。源码树与当前 main 完全相同。
GitHub run 总状态在交付时仍 in_progress，已原样记录在交付审计中；没有修改 download-ipa.ps1 的 success 门禁。本次使用已成功上传的 Artifact 做人工独立核验和本机交付。总状态仍待平台更新，不能表述为整个 workflow 已终结。
此为未签名开发版 IPA，用户需在自己的电脑使用 Sideloadly 签名安装。手机安装、覆盖保留数据、续签、真实账号查询与支付仍未验收；真实下单默认关闭，Token 在手机设置页填写。

## 2026-11-05 最终交付确认

运行 https://github.com/severus-S/luckin-random/actions/runs/41875870306 已 completed/success。使用原有 download-ipa.ps1 指定本成功 run ID 再次下载，来源 commit/run ID、SHA256 与 IPA 结构校验全部通过。此前 in_progress 为当时平台状态，现以此最终结果为准。
交付文件：artifacts/latest/LuckinRandom/LuckinRandom-unsigned.ipa，0.1.0 (4)，arm64，最低 iOS 17.0，Bundle ID com.sjx13.ios.luckinrandom。SHA256 e8c0dcb9885abef9cb417b4d4faf7b5efe27f10aa893de2a984a3c0e312763bd。旁附安装说明、manifest、SHA256SUMS 和交付审计。
27 项后端测试、6 项 Swift 测试、Xcode 编译、打包、上传及本机独立验证均通过。未签名、未安装或验收真实支付；用户使用本机 Sideloadly 签名安装，Token 在手机 App 设置页填写。HTTPS 后端及真实授权仍为后续独立事项。

## 2026-11-05 首次手机验收准备

用户反馈“现在签名到我手机上了”。记录为用户报告已完成签名并装到手机；尚未收到 App 启动、版本、咖啡池、模拟流程或持久化结果，不能据此把这些项目标为通过。当前安排离线模拟真机验收，HTTPS 后端尚未部署，真实订单、支付和自动任务不在本轮手机验收范围。

## 2026-11-05 手机离线验收通过（用户反馈）

用户在完成签名装机并收到六项离线测试清单后反馈“全部正常”。按该轮清单记录以下项目通过，证据类型为用户真机反馈，未独立操作或读取手机：

- App 启动、五个主页面切换及本轮基本布局操作。
- 模拟门店、咖啡池添加/规格配置、暂停与启用数量。
- 从启用候选随机预览，规格与金额展示。
- 模拟创建、模拟支付成功、模拟出餐与 MOCK 测试取餐号。
- 划掉 App 再打开后，咖啡池、规格、暂停状态及订单保留。
- 按清单导出配置、修改备注、导入备份后的配置恢复。

该反馈不等于统计分布的真机证明，也不覆盖深色/大字体专项、App Intents、覆盖升级、续签、真实 MCP 授权/商品/订单/支付、服务端调度或远程通知。后端尚未部署，真实下单仍关闭；下一阶段先确定 HTTPS 后端部署位置，再由用户在手机填写 Token 进行只读查询和预览。真实订单及付款另行授权。

2026-11-05：按用户请求只读盘点已有服务器连接。一个现有 VPS 已通过 SSH 登录验证，另一个历史公网 SSH 入口可达但本机默认密钥无效、未登录成功；详细地址与配置来源保存在被 Git 忽略的 .local/server-connection-audit.json，未公开基础设施信息。未修改服务器，Luckin Random 后端仍未部署，部署目标待用户选择。

## 2026-11-05 旧业务清理及 HTTPS 后端部署

用户明确授权先删除目标服务器全部旧业务再部署。已删除旧应用/数据库/备份/备份任务/中转/证书与半成品，保留系统、SSH、网络及云管理。旧业务备份不保留。重新生成独立 API 配对密钥与 AES 主密钥、新 SQLite 和 IP SAN 证书。新应用为单用户、单进程、非 root、loopback-only、systemd 开机/故障守护，内存/CPU 受限。小内存目标不再运行 TypeScript 编译；本机编译及测试后打包纯 JavaScript，目标 Node 22.23.4 的 27 项 Mock 测试全部通过。

公网可信 HTTPS/TLS 1.3 与 IP SAN 验证通过；缺失/错误认证 401，有效认证 200，跨站 403，反代覆盖伪造协议头，真实下单授权 403 DISARMED，无 Token 查询 401 TOKEN_REQUIRED。服务重启后配置相同、SQLite inode 保留；无真实订单或支付请求。服务 active/running，检查时 NRestarts=0，数据库 0600、环境 0640，Node 端口仅本机。详细地址与密钥均仅存 .local/deployment/，未提交仓库。手机后端配对、官方 Token/工具发现与真实查询尚未验收；整机重启、长期续期、异地备份及灾难恢复不由上述检查推定。

证书维护验收：目标证书 `certbot renew --dry-run --run-deploy-hooks` 已成功，Nginx 配置检查与 reload hook 成功；snap.certbot.renew.timer active。仅证明本次 ACME 演练、定时器及重载路径，不代表已跨越自然到期。程序/依赖目录归 root 且服务账号不可写，只有数据目录可写。部署脚本与本机运行包打包器已保存；新打包器实际运行成功。
