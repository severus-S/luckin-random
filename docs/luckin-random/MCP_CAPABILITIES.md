# 瑞幸 MCP 能力与证据

公开页面及资源获取于 2026-11-04，结果整理至 2026-11-05。

来源：[官方开放平台](https://open.lkcoffee.com/mcp)、[官方接口说明](https://open.lkcoffee.com/docs)。页面为 SPA，实际参数、输出及样例来自其公开 JS 资源 `index-LkJ8_EhP.js`。
保留来源 URL、SHA256 和八种**公开文档样例**于 reference/official-examples.json；这些样例包含测试域名/示例 ID，不可作为生产数据。

历史：2026-11-04 现有开发 Token 的 tools/list/初始化发现返回 401，未通过认证。

当前：2026-11-05 用户在手机填写新 Token 后，后端加密保存；目标服务器内只读解密并成功完成 initialize → initialized → tools/list，发现下表八个官方工具，保存实际 inputSchema。仅获取工具列表，没有执行 tools/call；门店、商品、规格与预览响应仍未实测。
未打印、写入 Git 或复制保存该 Token。账号新授权由用户在手机自行完成；没有创建、支付或取消真实订单。

| 能力/工具 | 官方公开文档 | 真实账号验证 | 已实现代码 |
|---|---|---|---|
| Streamable HTTP / Bearer | 明确提供指定端点 | 认证、初始化、8 工具 schema 发现成功 | 初始化、session、JSON/SSE、分页发现、实时 schema 参数校验 |
| queryShopList | 经纬度必填，门店名可选 | 已发现 schema，调用未实测 | 门店搜索和选择 |
| searchProductForMcp | deptId + query | 已发现 schema，调用未实测 | 商品搜索；不猜空 query 等于完整菜单 |
| queryProductDetailInfo | deptId + productId | 已发现 schema，调用未实测 | 详情、属性选项 |
| switchProduct | deptId/productId/skuCode/amount/attrOperationParam | 已发现 schema，调用未实测 | 按属性组、子选项、operation=3 切换并回验 |
| previewOrder | deptId + productList | 已发现 schema，调用未实测 | 核对门店、SKU、数量和官方价格；原样保存 couponCodeList |
| createOrder | 商品、门店坐标、可选 couponCodeList/remark | 未授权、未验证 | 已编码且真实合同门锁默认关闭 |
| queryOrderDetailInfo | orderId 字符串 | 已发现 schema，调用未实测 | 文档状态映射、取餐号提取；未知状态保守处理 |
| cancelOrder | orderId 字符串，返回 boolean | 未授权、未验证 | 先确认未付款，仅发送一次取消，随后查状态 |
| 完整菜单/商品分类 | 八工具说明未列出独立能力 | 未证实 | 真实模式降级搜索；Mock 有模拟分类 |
| 指定最优优惠券 | 预览只公开匹配结果 | 未证实 | 仅透传官方结果，不自行选券 |
| 支付宝/Universal Link/H5 收银台 | 未见明确官方能力 | 未证实 | 不生成虚构支付链接 |

## 官方授权方式

公开网页有手机号、短信验证码、协议同意、创建/查看 Token、Token 到期和撤销入口。
正式使用由用户在手机 App 中打开官方站点完成，再回到手机设置页填写/粘贴 Token；App 经自有已配对 HTTPS 服务验证后加密保存。不会调用网页内部登录/验证码接口。
网页代码中的 CLI 授权回调限定 HTTP 127.0.0.1，不能据此宣称存在适用于 iOS 的 OAuth 回调。

## 下一次只读验证

正常使用通过手机 App 的 Token 输入框执行只读验证；电脑环境变量不是用户必经步骤。仅开发诊断可在安全本机环境设置 LUCKIN_MCP_TOKEN 并运行后端 `npm run discover`，schema 写到被 Git 忽略的 artifacts/luckin-research/tools.schema.json。
用户明确提供门店位置并授权查询后：门店搜索 → 商品搜索 → 详情 → 规格切换 → 预览。逐项记录已测状态和脱敏字段结构；不调用 createOrder。
已拿到本轮实际 tools/list；公开网页响应样例仍不等于真实业务响应，Mock schema 也不是实时发现结果。

参考项目只用于了解已知限制，未复制其代码或采用其私有接口/绕过策略：[openluckin](https://github.com/shupianx/openluckin)、[luckin-mcp-proxy](https://github.com/wyhAcc/luckin-mcp-proxy)。
协议实现参照 [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)。

2026-11-05 后续真实验收：指定门店查询成功返回官方门店坐标；修复预览误要求消费授权后，以手机已保存配置完成一次只读详情/规格校验与官方预览，返回 previewed 和官方金额。创建、支付、取消仍未执行，LIVE_CONTRACT_VERIFIED 继续关闭；不能由一次预览推定全部商品、价格与支付响应已兼容。
