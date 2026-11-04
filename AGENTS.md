# Luckin Random 开发指导

1. 先读 docs/IOS_WORKFLOW.md 和 docs/luckin-random/PROGRESS.md，继续前核对已测/未测边界。
2. 复用既有 GitHub Actions 构建及 scripts/project.py，不在 Windows 运行 Xcode。
3. 用户本人进行所有电脑界面与手机操作；代理仅执行后台代码、命令和日志检查。
4. 正式使用的瑞幸 Token 在手机 App 设置页填写，经 HTTPS 验证并在后端加密保存。电脑环境变量仅用于开发诊断。
5. 默认 Mock，真实下单关闭。真实订单与付款需要用户明确授权；无法验证的支付能力不得编造。
6. 不提交 Token、私钥、Apple ID 密码、配对资料或真实订单数据。
7. 区分语法检查、Xcode 编译、签名、安装、续签、升级和真实支付验收。
8. 公共仓库仅使用标准 runner；不擅自使用付费服务、larger runner 或购买证书。
9. 新增 Swift 文件后重新生成工程；保留稳定 Bundle ID 和配置迁移兼容性。
10. 更新文档、VALIDATION.md 与 PROJECT_HISTORY.md；临时实验不标记为稳定结论。
