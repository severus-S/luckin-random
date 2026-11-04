# Luckin Random · 瑞幸随机咖啡

SwiftUI 原生客户端，最低 iOS 17.0，稳定 Bundle ID `com.sjx13.ios.luckinrandom`，版本 `0.1.0`。

目前是**待云端编译和真机验收的开发版本**，不能称为已交付可日常付款的正式 App。
默认离线模拟；真实查询需要有效 MCP Token 和 HTTPS 后端，真实创建额外受服务端合同验证与用户授权双重限制。

- 五个主页面：随机首页、多个咖啡池、自动任务、历史与抽取统计、设置。
- 本地 JSON 原子保存、版本检查、备份恢复；配对密钥使用 Keychain，备份不含认证信息。
- 官方商品搜索、详情与规格切换通过后端接入；不硬编码真实商品 ID。
- App Intents 提供“随机买一杯瑞幸”，打开 App 后执行。未实测 Siri/快捷指令。
- 小组件、主屏幕长按快捷操作和 APNs 尚未实现；没有引入需要额外 entitlement 的扩展。

开发入口：[进度](../../docs/luckin-random/PROGRESS.md)、[构建](../../docs/luckin-random/BUILD.md)、[架构](../../docs/luckin-random/ARCHITECTURE.md)。

```powershell
python scripts/project.py LuckinRandom
python scripts/selftest.py
# macOS（由现有 CI 执行）：swift test --package-path apps/LuckinRandom
```

首次本机体验（构建、签名安装成功后）：设置保持离线模拟 → 常用门店选择模拟门店 → 咖啡池添加模拟饮品 → 首页随机/预览 → 历史中模拟支付与取餐 → 导出备份。

模拟商品有明确“模拟”名称和独立 ID，付款二维码为空，不会混入真实支付渠道。
