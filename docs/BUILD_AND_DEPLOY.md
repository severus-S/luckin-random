# 编译与部署

复用 `build-ios.yml` 和 `scripts/ci_build.py`；不在 Windows 运行 Xcode。

- 工程生成：`python scripts/project.py LuckinRandom`
- 基础回归：`python scripts/selftest.py`
- 云端编译：推送 main 自动运行；需手动时运行 `scripts/build-ios.ps1 -Repo severus-S/luckin-random -App LuckinRandom -BillingChecked`
- 下载：`scripts/download-ipa.ps1 -Repo severus-S/luckin-random -App LuckinRandom -RunId RUN_ID`
- 安装：见 SIDELOAD_AND_RENEW.md，全部 GUI 与手机操作由用户完成。

编译不需要瑞幸 Token 或 Apple 凭据。Token 在手机 App 设置页填写。后端 HTTPS 部署独立于 IPA 构建。
