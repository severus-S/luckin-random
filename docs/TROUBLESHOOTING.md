# 故障排查

- 构建失败：检查准确 run ID 的失败步骤，下载 build.log；先修正真实编译错误，不把语法解析视为 Xcode 成功。
- Swift 新文件未包含：重新运行 scripts/project.py LuckinRandom。
- GitHub 排队：检查 GitHub 官方状态与 runner 分配，避免重复触发相同运行。
- Artifact 缺失/过期：3 天保留；仅下载成功运行并核对来源。
- 认证失效：在手机 App 设置中更新瑞幸 Token；不把 Token 写入聊天、日志或仓库。
- 创建结果未知：停止重新创建，有官方订单 ID 时只读查询，否则人工核对官方订单。
- 签名/安装：由用户按 Sideloadly 官方当次提示操作；不使用编译结果推断安装已成功。

新增条目应记录现象、证据、修改和验证范围。
