# Luckin Random 后端

Node.js 22.14+、TypeScript、SQLite（Node 内置 node:sqlite）。单用户、单进程部署；配对 API 密钥具有该实例的全部权限，不能共用于多租户。

```powershell
cd services/luckin-random
npm ci --ignore-scripts
npm test
Copy-Item config.example.env .env
# 自己生成两个独立随机密钥，填写 .env，勿提交；默认 mock、不消费
node --env-file=.env dist/src/main.js
```

Mock API 也要求配对密钥。iPhone 只接受 HTTPS 后端 URL；Windows 回环 HTTP 仅供自动化测试，不能作为手机服务器地址。生产需本机反向代理终止 HTTPS，覆盖 `X-Forwarded-Proto`，API 仅监听回环；本轮已按用户授权部署，维护流程见 `../../docs/luckin-random/DEPLOYMENT.md`；不自动开通付费服务。

账户授权在瑞幸官方网页由用户完成，然后在 App 设置中将 Token 通过已配对 HTTPS 连接提交。后端先做只读 schema 发现，验证成功才 AES-256-GCM 加密保存；密钥独立存放于服务环境。删除令牌会同时停止下单，官方撤销需用户操作。

`npm run discover` 从环境变量读取 Token，仅发现工具和 schema，不下单。实际响应适配器来自公开文档；在真实响应验收前保持 `LIVE_CONTRACT_VERIFIED=false`。即便打开此开关，还要求服务端允许、用户显式启用、紧急停止解除、消费限额全部通过。

已实现 API：状态、配置备份恢复、门店/商品搜索、详情/规格切换、随机预览/创建、状态查询/取消、Mock 支付结果、任务/执行记录、站内通知、紧急停止。见 `../../docs/luckin-random/ARCHITECTURE.md`。

数据库必须放在持久磁盘；备份 sqlite、WAL/SHM 时停服务或使用 SQLite backup，密钥另外加密备份。迁移按 migrations 版本向前升级；不删除数据库来升级。不要把 .local、.env、备份或订单二维码上传到 Git。

```powershell
# 独立模拟 MCP（另开终端），与官方端点完全隔离：
npm run mock:mcp
# http://127.0.0.1:8790/mcp；此处 schema 是合成测试数据，不是官方发现结果
```

普通 PUT /v1/config 不能改变紧急停止或真实下单授权。恢复任务/授权需 POST /v1/authorization，明确确认并记录当前消费限额快照；实际预算取当前限制与授权快照的较小值。
