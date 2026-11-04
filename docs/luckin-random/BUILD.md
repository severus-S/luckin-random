# 构建、安装与源码交付

本项目独立公共仓库：`severus-S/luckin-random`。复用现有 build-ios.yml，标准 macos-15，20 分钟超时，Artifact 保留 3 天。

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
