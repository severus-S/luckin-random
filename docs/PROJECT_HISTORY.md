# 项目历史

## 2026-11-04–05

创建 SwiftUI 原生应用和 TypeScript/SQLite 后端，完成咖啡池、随机、预算、防重、未知结果停止、调度、状态轮询、备份及 Mock MCP。
现有开发 Token 返回 401；官方文档样例、合成 Mock schema 与实时验证状态分开记录。真实下单与支付未验收。
用户明确 Token 在手机 App 设置页填写，并授权采用 Public 仓库。独立发布项目源码、测试和必要文档，复用既有标准 macOS runner 构建流程。

## 2026-11-05 公共仓库构建

公共仓库：https://github.com/severus-S/luckin-random 。首次源码提交 30bdfe01dbfd4a5ba5940d8e4dbc6d890eb774b0，通过 push 自动触发运行 https://github.com/severus-S/luckin-random/actions/runs/41869588528 。
当前仍等待 GitHub 分配 runner。官方同期公告 Actions/Webhooks 故障，已采取缓解措施但状态可能延迟；在看到真实成功结果前，不声称已有 IPA。标准 macos-15 runner，无付费 larger runner，无认证资料。

## 2026-11-05 服务恢复后重新触发

用户询问进度时，原公共 push 运行 41869588528 仍 queued。GitHub 官方状态已改为 operational，公告仍处于 monitoring；取消旧运行并确认 cancelled 后，使用既有 build-ios.ps1 触发一次新运行。
新运行：https://github.com/severus-S/luckin-random/actions/runs/41871798205 ，源码 a486f37b2dbb5f9daae40736b39cd8e342100c4d，当前 queued、未分配 runner，无编译日志或 IPA。保持单个活动构建，不将排队记为编译成功。

2026-11-05 队列审计：官方文档证实 macos-15 标签有效；API 证实 Actions 启用、无部署审批、无本仓库其他活动运行或错误注释。当前仍未分配 runner，保留唯一任务等待；不承诺排队时间或编译成功，不重复触发。详细证据见 luckin-random/VALIDATION.md。

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
