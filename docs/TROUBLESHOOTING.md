# 故障排查

- 构建失败：检查准确 run ID 的失败步骤，下载 build.log；先修正真实编译错误，不把语法解析视为 Xcode 成功。
- Swift 新文件未包含：重新运行 scripts/project.py LuckinRandom。
- GitHub 排队：检查 GitHub 官方状态与 runner 分配，避免重复触发相同运行。
- Artifact 缺失/过期：3 天保留；仅下载成功运行并核对来源。
- 认证失效：在手机 App 设置中更新瑞幸 Token；不把 Token 写入聊天、日志或仓库。
- 创建结果未知：停止重新创建，有官方订单 ID 时只读查询，否则人工核对官方订单。
- 签名/安装：由用户按 Sideloadly 官方当次提示操作；不使用编译结果推断安装已成功。

新增条目应记录现象、证据、修改和验证范围。

## 2026-11-05 队列配置复核

针对用户提供的截图，读取实际工作流、GitHub 当前 runner 文档和本次运行 API：

- runs-on 为 macos-15，官方当前列为免费标准 M1/arm64 runner；没有 self-hosted 或自定义 runner 标签。
- 仓库为 public、未 archived/disabled；Actions enabled=true，allowed_actions=all。
- 本次 check run 无错误注释，pending_deployments 为空；本仓库仅一项活动构建，前两项已取消，未发现本仓库并发锁或部署审批等待。
- 当前 run 41871798205 仍 queued，runner_id/runner_name 为空，steps 为空；没有 Xcode 编译证据或 IPA。
- GitHub 官方已恢复 operational，相关事故仍 monitoring。未据此推断积压队列全部恢复。

结论：当前未发现无效标签、仓库禁用或审批导致的等待，保留当前任务等待合理；无法承诺等多久或必然编译成功。截图的 10–30 分钟只是经验值，官方未提供该排队时长保证。官方 limits 中的 24 小时队列限制列在 self-hosted 类别，不能直接套用为本 GitHub-hosted job 的成功或超时保证。

来源：https://docs.github.com/en/actions/reference/runners/github-hosted-runners 、https://docs.github.com/en/actions/reference/limits 。未改 runner 配置、未重复触发任务。

2026-11-05：运行 41871798205 最终失败，check-run 注释明确报告 hosted runner 多次领取失败及 macOS arm64 capacity constraints，steps 为空。标签与权限有效不代表资源可用；此前记录为当时状态，不作为成功保证。使用独立 codex/luckin-random-intel 分支测试官方免费标准 macos-15-intel，不改默认 main 的稳定配置，待真实构建验证后再决定合入。

2026-11-05 Intel 实测：运行 41875147576 成功分配免费标准 macos-15-intel，27 项后端测试和 6 项 Swift 核心测试通过；Xcode 16.4 / iPhoneOS SDK 18.5 已实际进入编译。AppStore 初始化中的局部 error 与 catch 隐式 error 冲突导致编译失败，已改名 loadFailure，等待真实复测。此失败是源码编译错误，区别于之前 ARM runner 分配失败。
