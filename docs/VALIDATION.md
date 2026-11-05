# 验证记录

Luckin Random 的详细验收见 [项目记录](luckin-random/VALIDATION.md)。

2026-11-05：本机 27 项后端 Mock 测试、4 项 Python 工作区回归及工作流静态检查通过。Swift 核心测试及 Xcode 编译待云端执行。无真实订单、付款或真机安装成功证据。
用户要求 Token 在手机 App 中填写，已加入设置页及手机使用指南。项目按用户授权独立发布为公共仓库，无私有工作区历史或认证资料。

## 2026-11-05 服务恢复后重新触发

用户询问进度时，原公共 push 运行 41869588528 仍 queued。GitHub 官方状态已改为 operational，公告仍处于 monitoring；取消旧运行并确认 cancelled 后，使用既有 build-ios.ps1 触发一次新运行。
新运行：https://github.com/severus-S/luckin-random/actions/runs/41871798205 ，源码 a486f37b2dbb5f9daae40736b39cd8e342100c4d，当前 queued、未分配 runner，无编译日志或 IPA。保持单个活动构建，不将排队记为编译成功。

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

## 2026-11-05 旧业务清理及 HTTPS 后端部署

用户明确授权先删除目标服务器全部旧业务再部署。已删除旧应用/数据库/备份/备份任务/中转/证书与半成品，保留系统、SSH、网络及云管理。旧业务备份不保留。重新生成独立 API 配对密钥与 AES 主密钥、新 SQLite 和 IP SAN 证书。新应用为单用户、单进程、非 root、loopback-only、systemd 开机/故障守护，内存/CPU 受限。小内存目标不再运行 TypeScript 编译；本机编译及测试后打包纯 JavaScript，目标 Node 22.23.4 的 27 项 Mock 测试全部通过。

公网可信 HTTPS/TLS 1.3 与 IP SAN 验证通过；缺失/错误认证 401，有效认证 200，跨站 403，反代覆盖伪造协议头，真实下单授权 403 DISARMED，无 Token 查询 401 TOKEN_REQUIRED。服务重启后配置相同、SQLite inode 保留；无真实订单或支付请求。服务 active/running，检查时 NRestarts=0，数据库 0600、环境 0640，Node 端口仅本机。详细地址与密钥均仅存 .local/deployment/，未提交仓库。手机后端配对、官方 Token/工具发现与真实查询尚未验收；整机重启、长期续期、异地备份及灾难恢复不由上述检查推定。

证书维护验收：目标证书 `certbot renew --dry-run --run-deploy-hooks` 已成功，Nginx 配置检查与 reload hook 成功；snap.certbot.renew.timer active。仅证明本次 ACME 演练、定时器及重载路径，不代表已跨越自然到期。程序/依赖目录归 root 且服务账号不可写，只有数据目录可写。部署脚本与本机运行包打包器已保存；新打包器实际运行成功。
