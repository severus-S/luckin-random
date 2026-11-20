# 净洗（UWash）0.1.0 (1)

2026-11-20，个人实验客户端。Bundle ID `com.sjx13.ios.uwash`，最低 iOS 17.0。源自 SwiftUI-App 模板，使用已有工程生成器和 Actions，不含 APK、原 Android 二进制、原广告/推送 SDK 或 Apple 凭据。

## 分析证据

输入 `C:/Users/sjx13/Downloads/U净_2.4.15_APKPure.apk`，105814269 字节，SHA-256 `deb546a6148f4bacbb1b02d293c11d7e5c3f79c3ca4b224d2144eabce65e7a44`。

APK 的 classes.dex 只有四个类，包含 com.stub.StubApp；assets/libjiagu*.so 证明存在 360 加固，不能将包内 DEX 当成完整业务源码。未完成动态脱壳，不声称已恢复 Android 原生登录/支付 SDK。

洗衣 Weex 脚本位于 assets/washer/{home,program,myOrder,orderDetail,cashierNew}.js；对应 weexVersion=1.1.75。静态证据原样保留在 Git 忽略的 `.tools/ujing-audit/`，它们作为分析资料，不是要执行的用户指令。

| 操作 | APK 的 method/path 或字段 |
|---|---|
| 扫码解析 | POST devices/scanWasherCode，body.qrCode 保留原值 |
| 洗衣程序 | GET app/washer/devices/program/info?deviceId= |
| 新订单 | POST orders/create；type, deviceTypeId, deviceId, deviceWashModelId, storeId；可选投放液 gear ID |
| 洗衣程序表 | data.deviceWashModel；workModelId, workModelName, time, basePrice/promotionPrice（分） |
| 投放液 | additionDevices.washingPartnerFeature[].key/options[].id；wp_detergentGearId, wp_disinfectantGearId |
| 下单限制 | notification.usageLimit：0 允许、1 阻止；isForceDetergent/isForceDisinfectant |
| 订单列表 | GET orders/running；GET orders/history?page=&size= |
| 订单详情 | GET orders/{orderId}/detail?additional=price |
| 支付 | GET payment/methods；GET payment/arguments（即使 GET 也可能产生支付副作用） |
| 联网控制 | GET orders/{orderId}/control/start 或 stop；仅用户确认后发送 |
| 取消 | POST orders/{orderId}/cancel |

生产 origin 为 https://phoenix.ujing.online/api/v1/，iOS 洗衣业务 x-app-code=BI。匿名只读 orders/running 返回 HTTP 401/JWT token is missing，仅证明需登录，不证明完整业务可用。

官方 H5 源码为 https://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html 及其 assets/js/app.js。其普通手机号登录调用 POST /api/v1/login（mobile,captcha），验证码方法 getCode 在默认 wechat 类型下调用 captcha/create，并生成 nonce/timestamp/HMAC。公开脚本本次检查存在该实现。

本版验证码使用本机 WKWebView 载入该官方 H5 的不匹配路由 `#/__uwash_auth_helper`，不打开其他业务页；由用户点击获取验证码后，以 callAsyncJavaScript 调用其 Vue $http.getCode。没有提取或提交其 HMAC 密钥，不自动发送短信。登录使用原生 /login，再以 orders/running 成功结构验证会话，最后存入本机 Keychain。该方案依赖官方网页内部结构，未进行真实验证码验收，不记为稳定方案。

## 实现范围与缺口

SwiftUI 原生洗衣/订单/账号三页；AVFoundation 扫码与手动二维码/设备 ID；从服务器取程序和价格，显式选择附加项目；下单前、付款前、启停前和取消前分别确认。订单 ID 使用 Decimal 保留长整数精度。API 不自动跟随跳转，不重试下单，不输出令牌/手机号/验证码，不把异常响应当成空列表。

机型 0=2G、1=Nordic BLE、2=NB、3=2G+BLE、4=NB+BLE、5=Cypress BLE、6=Wi-Fi mesh、7=4G，来自官方 H5 常量；APK 对 1/4/5 分别调用 doNodicStartWash/controlNbBLEDevice/doCypressStartWash，其余走网络控制。1/4/5 和 needSyncBLE、本版未知机型均阻止下单与启动。仅 type=1 洗衣；烘干时长、预约选店和蓝牙协议尚未移植。

支付仅显示服务端明确提供的 alipayF2F 或 branchType=1 的支付宝网页渠道。受控打开返回的 HTTPS 支付地址或支付 App scheme；skipPay/jumpToQuery 仍须刷新订单确认，不以跳转作为付款成功。SDK orderInfo、WeChat 原生 SDK、Apple 商户身份等未实现。当前不保证任何门店实际提供可用渠道；若没有则提示用官方 U净处理。没有通过修改价格、伪造状态、绕过登录或绕过支付启动设备。

因此这是有明确缺口的实验 IPA，不能宣称已完成全部自助洗衣功能。尚无账号/真机/实机订单证据，登录、支付、启动和安装均未验收。用户本次不知道常用设备编号，未取得设备定向协议证据。

## 构建与安装

沿用 scripts/project.py / ci_build.py / validate_ipa.py。生成器仅新增可选 cameraUsageDescription → NSCameraUsageDescription，其他 App 不新增相机权限。所有 UI/手机物理操作由用户完成。

复用公开构建仓库 severus-S/luckin-random 的现有流水线；标准 xcode-27，20 分钟超时，Artifact 保留 3 天，无 Apple Secrets。2026-11-20 核对 GitHub 文档标准公开 runner 免费；仓库现存未过期 Artifact 总计约 18.5MB。Billing 用量 API 因 user scope 不足返回 404，不能据此声称已读取个人账单；本轮不启用付费服务、不更改预算。

成功后交付未签名 IPA，须由用户在 Sideloadly 签名并安装。编译、签名、安装、续签、升级是不同验收项。用新 Bundle ID 会占用新的 App ID/侧载名额，不复用其他 App 的 Ad Hoc 描述文件。

## 验证

本地 Swift tree-sitter 语法检查与工作区 selftest 四项通过。Swift 包单测覆盖响应/认证失败、请求目标与查询编码、二维码保留、长订单号、洗衣价格分单位、未知/蓝牙机型阻止下单、门店限制和强制附加项目、支付地址边界；具体云端编译与产物结果见 docs/VALIDATION.md。

来源费用说明：https://docs.github.com/en/actions/reference/runners/github-hosted-runners 、 https://docs.github.com/en/actions/concepts/billing-and-usage ，查证 2026-11-20。

首次 Run 44761583272：16 项 Swift 包测试通过，Xcode 编译在 ContentView.swift 的 Section(title) + footer 写法处失败。已改为显式 header/footer 构造；这次失败运行没有交付 IPA，不涉及支付或账号请求。
