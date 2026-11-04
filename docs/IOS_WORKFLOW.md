# iOS 操作手册

此仓库为 Luckin Random 独立公共项目。详细功能状态见 luckin-random/PROGRESS.md。

1. Windows 开发：SwiftUI 源码位于 apps/LuckinRandom/Sources，后端位于 services/luckin-random。
2. 新增 Swift 文件后执行 `python scripts/project.py LuckinRandom`；执行 `python scripts/selftest.py` 验证构建基础设施。
3. 后端执行 `npm ci --ignore-scripts` 和 `npm test`，测试仅使用 Mock。
4. 推送 main 会调用既有 `.github/workflows/build-ios.yml`，标准 macos-15-intel runner 运行后端测试、Swift 核心测试、Xcode Release iphoneos arm64 无签名构建。
5. CI 核对 plist、arm64 Mach-O、未签名状态、ZIP CRC；输出 manifest 与 SHA256SUMS。真实编译成功后才能称为 IPA 产物。
6. `scripts/download-ipa.ps1 -Repo severus-S/luckin-random -App LuckinRandom -RunId RUN_ID` 下载并校验指定成功运行。
7. 用户在本机 Sideloadly 中输入自己的 Apple ID，完成签名、二次验证和手机安装；密码不交给代理或 CI。
8. 真机启动后先测试离线模拟、持久化和备份恢复。Token 在手机 App 设置页填写，正式后端部署需单独确认。
9. 更新使用相同签名身份及有效 Bundle ID 覆盖安装，避免卸载导致数据丢失；版本更新、续签与后台刷新独立验收。
10. 所有电脑界面和手机操作均由用户本人完成；无真机证据不声称安装或续签成功。

公共仓库标准 runner 计算免费；仍有并发、存储、超时等限制。工作流只用标准 macos-15-intel、20 分钟超时、3 天 Artifact 保留，不开通付费服务。
