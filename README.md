# Luckin Random · 瑞幸随机咖啡

SwiftUI 原生 iOS App + TypeScript/SQLite 后端，通过瑞幸官方 MCP 查询和点单。非瑞幸官方 App。

**开发版本：默认离线模拟，真实下单关闭。真实账号、支付、真机安装尚未验收。**

## 功能

- 多个咖啡池、独立规格、启停、等概率/加权随机、避免重复、备份恢复。
- 官方查询适配器、订单预览、预算预留、幂等、防重复和超时未知结果阻断。
- 服务端定时任务、执行记录、状态轮询、站内通知和紧急停止。
- 手机 App 设置页填写瑞幸 Token，经 HTTPS 验证后由后端加密保存；不需要在电脑填写 Token。
- 独立 HTTP Mock MCP 和自动测试，无真实消费。

## 开始

```powershell
cd services/luckin-random
npm ci --ignore-scripts
npm test
```

iOS 使用既有 GitHub Actions `build-ios.yml`、标准 `macos-15` 构建未签名 IPA，用户在本机通过 Sideloadly 签名安装。

[手机使用指南](docs/luckin-random/USER_GUIDE.md) · [构建安装](docs/luckin-random/BUILD.md) · [当前进度](docs/luckin-random/PROGRESS.md) · [支付能力](docs/luckin-random/PAYMENT_TEST.md) · [安全边界](docs/luckin-random/SECURITY.md)

公共仓库标准 GitHub-hosted runner 计算免费；存储、并发及服务可用性仍受相应规则限制。Artifacts 保留 3 天，不使用 larger runner，不提交任何凭据。
