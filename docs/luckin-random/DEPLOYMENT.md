# 单用户后端部署与维护

2026-11-05：用户已明确授权清除目标主机的旧业务并全新部署。旧网站、数据库及备份、定时备份任务、中转、旧证书和上次部署残留已删除；保留系统、SSH、网络与云管理组件。详细地址、配对资料、包哈希与验收证据仅存 Git 忽略目录 `.local/deployment/`。

## 当前结构

- Nginx 80 端口仅服务 ACME 验证，其余路径 404；443 为新后端 HTTPS。
- Node.js 22.23.4 官方 Linux x64 包，安装前核对官方 SHA256；不替换系统 Node。
- 后端只监听 `127.0.0.1:18787`，反代覆盖 `X-Forwarded-Proto=https`。运行账户 `luckin-random` 无登录 shell。
- systemd 开机启动、异常重启、140 MiB 内存上限及 CPU 限制；单用户、单实例、单进程。
- 程序在 `/opt/luckin-random/current`；持久 SQLite 在 `/var/lib/luckin-random/`；独立随机 API 密钥与加密主密钥在 `/etc/luckin-random/server.env`，root 所有、服务组可读、0640。SQLite 0600，数据目录 0750。
- 部署时显式选择 `MCP_MODE=live` 仅供真实查询。`ALLOW_LIVE_ORDERS=false`、`LIVE_CONTRACT_VERIFIED=false`、默认真实授权关闭、紧急停止开启。未填写官方 Token、未创建真实订单。
- 使用可信 IP SAN 证书，无需配置域名。该类证书有效期约 160 小时，必须保持 ACME 的 80 端口和续期定时器正常；本轮 renew --dry-run --run-deploy-hooks、Nginx 重载与 active 定时器检查通过；不能把一次签发或演练当作已跨自然到期的长期续期证明。

## 打包与首次安装

Windows 执行 `python scripts/package-luckin-server.py`，本机完成编译、Mock 测试和锁定依赖安装，输出 `artifacts/luckin-server/backend-runtime.tar.gz` 及 SHA256。仅当前依赖全部是纯 JavaScript 时可跨平台打包；检测到 `.node` 必须改用目标平台构建。不得在小内存服务器运行 TypeScript 编译。

将运行包与 `scripts/deploy-luckin-server.sh` 经已验证主机密钥的 SSH 上传。首次安装脚本要求 root，以及 `PUBLIC_IP`、`PACKAGE`、`PACKAGE_SHA256`、`RELEASE_ID`，可选 `TLS_PORT`（默认 443）、`BACKEND_PORT`（默认 18787）、`MCP_MODE`（默认 mock）。真实查询必须显式指定 live。脚本不负责清空主机，不得对其他服务器套用本轮清理命令。

先确认端口空闲且没有旧实例；脚本会拒绝覆盖现有 systemd 部署。它会申请免费证书；新 ACME 账号使用无邮箱注册，需要维护者自行检查续期结果。目标侧仅运行受内存/CPU/90 秒超时限制的已编译 Mock 测试，测试通过才启动服务。首次脚本失败后应检查具体阶段，不要直接重跑或重新生成主密钥。

## 升级与恢复

1. 本机打包并测试，核对 SHA256。可用 `scripts/upgrade-luckin-server.sh`，传入 PACKAGE、PACKAGE_SHA256、RELEASE_ID；目标先做受限测试，再停服务备份并切换，保持 root 所有、服务账号只读。环境文件不会被改写，失败回退前先核对数据库迁移版本。
2. 停止 `luckin-random`，通过 SQLite backup API 备份数据库；环境密钥另行加密备份。备份含私人配置或订单，不得提交仓库。
3. 保持 `/var/lib/luckin-random/`、现有环境密钥及 Bundle ID，切换 current 符号链接后启动。迁移向前执行；禁止以删除数据库解决升级问题。
4. 验证 HTTPS、状态、配置及进程。若数据库版本没有变化，可停服务并切回上一 release；已迁移的数据必须使用兼容程序或经过审计的备份恢复，不能盲目降级。

本轮仅验证 service restart 保留同一 SQLite 及配置；不等于整机重启、主机丢失恢复、磁盘加密或长期稳定性验收。尚未配置异地自动备份与远程告警。

## 手机配对

在本机私有 `手机后端配对.txt` 读取地址和后端配对密钥。手机 App → 设置 → 连接 HTTPS 后端 → 保存密钥并验证连接。随后在手机官方平台获取 MCP Token，回手机 App 验证并加密保存。配对密钥与官方 Token 是两项不同信息；Token 不交给聊天、电脑环境变量或 GitHub。

首次连接不会自动上传本机配置。需要保留手机咖啡池时，先备份，再点击“将本机配置同步到后端”；服务端仍保留关闭的真实授权和紧急停止。离线 Mock 门店与商品不能当作真实 SKU；连接真实查询后需重新选择官方门店和商品。真实查询及手机 TLS 连接需用户另行反馈，真实创建/支付另行授权和验收。
