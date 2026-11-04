# 项目历史

## 2026-11-04–05

创建 SwiftUI 原生应用和 TypeScript/SQLite 后端，完成咖啡池、随机、预算、防重、未知结果停止、调度、状态轮询、备份及 Mock MCP。
现有开发 Token 返回 401；官方文档样例、合成 Mock schema 与实时验证状态分开记录。真实下单与支付未验收。
用户明确 Token 在手机 App 设置页填写，并授权采用 Public 仓库。独立发布项目源码、测试和必要文档，复用既有标准 macOS runner 构建流程。

## 2026-11-05 公共仓库构建

公共仓库：https://github.com/severus-S/luckin-random 。首次源码提交 30bdfe01dbfd4a5ba5940d8e4dbc6d890eb774b0，通过 push 自动触发运行 https://github.com/severus-S/luckin-random/actions/runs/41869588528 。
当前仍等待 GitHub 分配 runner。官方同期公告 Actions/Webhooks 故障，已采取缓解措施但状态可能延迟；在看到真实成功结果前，不声称已有 IPA。标准 macos-15 runner，无付费 larger runner，无认证资料。
