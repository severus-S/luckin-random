# 构建、安装与源码交付

本项目独立公共仓库：`severus-S/luckin-random`。复用现有 build-ios.yml，标准 macos-15-intel，20 分钟超时，Artifact 保留 3 天。

公共仓库标准 runner 计算免费；存储与并发仍受 GitHub 规则限制，不使用 larger runner 或付费服务。2026-11-05 用户已明确授权 Public 发布及本次构建。

## 本地检查

```powershell
python scripts/project.py LuckinRandom
python scripts/selftest.py
cd services/luckin-random
npm ci --ignore-scripts
npm test
npm run mock:mcp
```

Swift 核心测试由 macOS 执行 `swift test --package-path apps/LuckinRandom`。只有真实 Xcode 构建成功才交付 IPA。

## 云端构建与下载

推送 main 自动触发一次，不重复 dispatch。手动构建和下载可用：

```powershell
pwsh -File scripts/build-ios.ps1 -Repo severus-S/luckin-random -App LuckinRandom -BillingChecked
pwsh -File scripts/download-ipa.ps1 -Repo severus-S/luckin-random -App LuckinRandom -RunId RUN_ID
```

下载后稳定路径为 `artifacts/latest/LuckinRandom/LuckinRandom-unsigned.ipa`。核对成功 run ID、源码 commit、manifest、SHA256 和稳定 Bundle ID `com.sjx13.ios.luckinrandom`。
编译无需瑞幸 Token 或 Apple 凭据。签名、安装、真机启动、数据保持和支付分别验收。

## 手机配置

用户在本机 Sideloadly 完成签名与安装后，先测试离线模拟。实际使用的瑞幸 Token **在手机 App 设置页填写**，无需电脑环境变量；后端 HTTPS 部署需另外完成。详见 USER_GUIDE.md。

## 源码包

`python scripts/package-luckin.py` 生成源码 ZIP，不含凭据、依赖、运行数据或 IPA；它不能代替云端编译产物。

## 2026-11-05 IPA 交付

已把真实编译产物整理到 artifacts/latest/LuckinRandom/LuckinRandom-unsigned.ipa，旁附 manifest.json、SHA256SUMS、安装说明和 delivery-audit.json。版本 0.1.0 (4)，SHA256 e8c0dcb9885abef9cb417b4d4faf7b5efe27f10aa893de2a984a3c0e312763bd。
交付前再次核对：唯一作业的所有步骤均已 completed，测试/编译/上传/Complete job 为 success；原始日志证实后端 27/27、Swift 6/6、BUILD SUCCEEDED；本机对真实 Payload/Info.plist/Mach-O/ZIP/哈希及来源 commit/run ID 全部核验。源码树与当前 main 完全相同。
GitHub run 总状态在交付时仍 in_progress，已原样记录在交付审计中；没有修改 download-ipa.ps1 的 success 门禁。本次使用已成功上传的 Artifact 做人工独立核验和本机交付。总状态仍待平台更新，不能表述为整个 workflow 已终结。
此为未签名开发版 IPA，用户需在自己的电脑使用 Sideloadly 签名安装。手机安装、覆盖保留数据、续签、真实账号查询与支付仍未验收；真实下单默认关闭，Token 在手机设置页填写。
