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

2026-11-05 手机反馈“后端配对密钥无效”：重新通过严格主机密钥 SSH 与公网可信 HTTPS 检查，交付配对文件中的 64 字符密钥与服务器配置一致，二者 /v1/status 均 200；hasToken=false、真实下单仍关闭。未读取或改动官方 Token，未轮换密钥。生成本机忽略目录内仅含 64 字符、无标签/换行的 pairing-key.txt，等待用户覆盖手机字段后重试；手机所存内容尚未读取，原因与真机恢复未确认。

2026-11-05 用户在重新填写配对密钥后反馈“连上了”。按用户真机反馈记录：本轮手机 HTTPS 后端连接及配对认证通过，未独立操作手机。此前公网自动认证检查亦通过；手机保存的密钥内容未读取。仅证明配对恢复，不代表官方 Token 已验证、真实查询、订单或支付通过。下一步由用户在手机 App 设置页填写官方 Token，验证并加密保存，再做只读门店/商品查询；真实下单继续关闭。

2026-11-05 手机 Token 授权后验收：公网 /v1/status 返回 hasToken=true；真实下单不可用，配置 realOrdersEnabled=false、emergencyStop=true。目标服务器内以只读 SQLite 连接读取加密记录，在服务器内存解密并执行 initialize → notifications/initialized → tools/list，成功发现 8 个官方工具。Token 未输出、未下载至电脑、未提交仓库；工具 schema 仅保存于受保护服务器和本机忽略目录。本次仅发现工具，没有调用 tools/call，没有创建、付款或取消订单。服务端尚未同步门店/真实候选；真实门店、商品、规格、预览的响应合同仍待验证。

## 2026-11-05 修复真实只读预览误要求消费授权

用户真机截图显示所有候选因“尚未明确授权消费上限”失败，不能视为预览成功。根因是预览与创建共享预算函数，真实模式无条件要求已授权消费快照。修复后仅只读 preview 可在没有消费快照时按当前预算检查；已有快照仍取较小上限，实际创建前继续强制所有授权门和快照。预览不会授予消费权限，也不会写授权快照。

新增 3 项回归先复现失败，修复后本机及目标 Linux 各 30/30 Mock 测试通过，覆盖未授权预览、超预算/已授权上限、无快照禁止创建及零创建调用。采用新 release 切换，停服务 SQLite backup 完整性通过；服务环境 SHA256、加密 secrets 与配置前后完全相同，保留门店/候选/历史。线上通过用户已有配置发起一次 previewOnly=true，返回 previewed、有效官方金额；无官方订单 ID/付款链接，已有官方 ID 数量未增加，真实下单仍关闭、紧急停止开启。未请求开启真实授权、未创建/支付/取消真实订单。

这次仅更新后端，没有修改 Swift 或重新签名安装 IPA。客户端需关闭旧失败记录后重新点击只预览；手机对本修复的回归尚待用户反馈。诊断详情及原始业务结果只存本机忽略目录，未公开。
