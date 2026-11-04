# Luckin Random 维护入口

先遵守根 AGENTS.md 和 docs/IOS_WORKFLOW.md，再读 docs/luckin-random/PROGRESS.md、MCP_CAPABILITIES.md、PAYMENT_TEST.md、SECURITY.md。

电脑界面和手机操作均由用户执行。仅后台代码、命令和日志检查由代理执行。
Mock 测试、Swift 语法解析、Xcode 构建、签名安装、真机运行、官方下单、付款和续签是独立验收项。
官方公开文档样例不等于实时 schema；无有效授权时不得声称实时发现成功。
不得为获得演示效果打开 LIVE_CONTRACT_VERIFIED 或真实下单开关。真实订单和支付测试需用户明确授权。
新增 Swift 文件后使用根 scripts/project.py 重新生成工程。保持稳定 ID 和 v1 配置兼容；升级不得删除用户数据。
正式使用时 Token 必须由用户在手机 App 设置页填写/粘贴，经 HTTPS 验证并在后端加密保存；电脑环境变量仅限开发诊断，不作为普通用户配置步骤。
