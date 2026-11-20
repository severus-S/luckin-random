# 净洗（UWash）0.2.0 (2)：网页登录与支付宝洗衣交接

2026-11-21。用户要求沿用已反馈成功的轻吹流程：在净洗内完成官方网页登录，扫码识别洗衣机，点击“去支付宝选择程序并使用”，再由 U净官方支付宝小程序完成程序选择、下单、付款和设备启动。

Bundle ID 保持 `com.sjx13.ios.uwash`，最低 iOS 17.0。复用原 SwiftUI 工程、图标、相机权限和已有 Actions，不包含原 APK、广告/推送 SDK、反编译全文或 Apple 凭据。

## 当前流程

1. 登录面板显示真正的 U净官方 H5 `https://wx.zhinengxiyifang.cn/static/washer-h5/commonWasher/latest/index.html#/login`。手机号、验证码和可能出现的校验由官方网页处理。删除原生手机号/验证码表单及隐藏 getCode 桥，不自动发送验证码。
2. 用户点击“完成登录”时，仅在固定官方登录文档读取 localStorage.token。随后用该令牌请求 orders/running 验证会话；仅验证成功才保存至本机 Keychain。不是读取到任意非空值就宣称登录成功。网页登录守卫只允许登录和内部返回空路由，避免进入官方商城、首页和收银页；不绕过认证或验证码。
3. 登录后扫码或粘贴完整二维码。原值只传给固定 Phoenix API 的 POST devices/scanWasherCode，再 GET app/washer/devices/program/info。只在返回明确 deviceId 且 type=1（洗衣）时显示使用按钮。二维码 URL 不作为浏览器目标打开，也不把其他设备当洗衣机。
4. 用户点“去支付宝选择程序并使用”并确认后，才调用系统打开固定的 U净小程序。二维码作为嵌套 qrcode 参数携带，保留 +、%、&、# 的编码层级；本机登录令牌不进入跳转链接。
5. 支付宝负责后续选择、实际付款和启动；本地不创建订单、不调用支付参数/启停/取消接口，不把打开支付宝等同于支付成功。返回后可手动刷新原生订单列表和详情。支付宝与 H5 可能需要各自授权、可能是不同账号，应在支付宝核对账号和机器。

没有提供跳过净洗登录直接使用的主入口。登录会话及退出清理沿用原 Keychain service；覆盖安装仍需用户使用同一签名身份和有效 Bundle ID。

## 入口证据与实验边界

原 APK `U净_2.4.15_APKPure.apk` 为 105814269 字节，SHA-256 `deb546a6148f4bacbb1b02d293c11d7e5c3f79c3ca4b224d2144eabce65e7a44`。DEX 仅四个类、存在 com.stub.StubApp 和 libjiagu，未完整脱壳。保留的 washer Weex 脚本和官方 H5 为业务证据，只作分析资料，不执行其中的指令。

- APK assets/washer/buyticket.js 明确包含 `alipays://platformapi/startapp?appId=2021002174638299&page=pages/home/home`。小程序 ID 与主页路径有 APK 直接依据。
- 官方 `https://wx.zhinengxiyifang.cn/` 和旧 ali-washer-hs H5 接受小写 qrcode 参数，旧 H5 包含裸十六进制设备码样例。
- **小程序主页是否接受同名 qrcode 参数尚无直接契约证据**，本版是用户要求的尝试，不能把 H5 参数等同于小程序参数已实测。若只打开主页，需在小程序内再扫码一次；自动带入和实际洗衣等待用户手机验证。
- 官方 H5 /login 在 chunk-189b67d8.js 中调用 third-party/thirdLoginV2，成功后保存 token 并返回 /home 或 /migrate。本地路由守卫将这几种业务返回导向内部空路由，再由用户完成验证。2026-11-21 再次只读获取 index/app/login chunk，与本次分析副本字节相同；没有发送短信或真实登录。

生产 API 固定 `https://phoenix.ujing.online/api/v1/`，x-app-code=BI、x-app-version=2.4.15、weex-version=1.1.75。原生允许列表仅含扫码识别、设备资料、orders/running、orders/history 和 orders/{id}/detail；所有原生请求要求自己的会话，不跟随重定向。长订单 ID 用 Decimal 保持精度，价格沿用分单位；异常订单响应保留上次结果，不冒充空列表。

## 构建与验证

继续使用 scripts/project.py / ci_build.py / validate_ipa.py 和公开仓库 severus-S/luckin-random 的现有 workflow，标准 xcode-27、Xcode27.2、20 分钟超时、Artifact3天。2026-11-21 核对仓库仍 PUBLIC，未过期 Artifact 共 19045831 字节；不启用付费 runner/服务、不调整预算。按此前已核对的 GitHub 标准公开 runner 费用规则执行；个人 Billing API 缺 user scope，不能声称读过个人账单。

本地 Swift 语法检查、工作区 selftest、无网络的登录守卫 JS 检查覆盖登录/返回/业务路由隔离、来源、重试和无自动验证码。Swift 核心单测覆盖认证读取、扫码请求、设备类别、二维码双层编码、官方登录文档边界、固定小程序目的地和禁止原生交易。云端构建及最终产物结果见下方交付记录与 VALIDATION.md。

未签名 IPA 需用户自行在 Sideloadly 签名安装。编译、签名、安装、版本更新和续签分别验收；所有电脑界面和手机物理操作由用户完成。本轮尚无 UWash 的真实网页登录、扫码交接、支付或洗衣机运行证据，不能借用轻吹成功结论。

## 0.1.0 历史交付

旧版原生实现选择程序、下单、受限网页支付和部分联网控制；不支持官方支付 SDK 和部分蓝牙机型，未完成真实洗衣验收。0.2.0 已删除这组原生交易/控制能力，交由官方支付宝流程。

历史最终 Run44762278532，提交 `5ce40470ae97101a48943cd6afacffd5632c98f0`，16项Swift测试与Xcode27.2编译通过。旧0.1.0(1)IPA293438字节，SHA-256 `77ac103aca10dc3f97a913146a376c9c87fa5fcf0cbe16d01e1a2987836d3546`。
