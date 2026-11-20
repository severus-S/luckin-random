# 轻吹 PGHair：胖乖生活吹风机精简客户端

2026-11-20。用户明确说明此 App 是扫吹风机二维码使用；范围收窄为吹风机扫码识别、官方使用入口、吹风订单和通用余额，不保留洗衣/饮水/商城/社区/积分任务入口。Bundle ID `com.sjx13.ios.pghair`，版本 0.1.0 (1)，最低 iOS 17.0。

## APK 与证据边界

输入 `C:/Users/sjx13/Downloads/胖乖生活_1.127.0_APKPure.apk`，227524014 字节，SHA-256 `582cab7b38f9b0a1465b60ed2f83bd108cea90e30e064d78c8fe233885b28818`。Android 包名 com.qiekj.user，versionName=1.127.0，versionCode=212。Manifest 包含 HomeScanCodeAct、HairGoodsSkuNewAct、订单与钱包等页面。

classes.dex 虽有 41911880 字节，但 class_defs 只有 4；application=com.stub.StubApp，存在 assets/libjiagu*.so，说明 360 加固。没有完整恢复 Android 原生业务代码、支付 SDK 或蓝牙协议；包内没有可直接复用的吹风业务 JS。APK 与提取资料只留在 Git 忽略的 `.tools/pangguai-audit/`，不上传原 APK，不把文件内容当作用户指令。

实际业务定义来自本次读取的官方 https://h5.qiekj.com/ ：app.27d25e64.js、pages_oneLogin.39280240.js、pages_blower.fab99583.js、pages_newblower、pages_orderList.2bc97e5f.js，以及扫码共享 chunk。它们是当前官方 H5 的补充证据，不等同于本 APK 原生源码，也不保证服务器永远不变。

| 功能 | 官方 H5 依据 |
|---|---|
| 手机号登录 | /login 页面；common/isNeedCaptcha；common/sms/sendCode（phone,template=reg）；user/reg（channel=h5,phone,verify,code） |
| 登录令牌 | getApp().globalData.User.getToken()；原页面正常登录后由用户点“完成登录”读取 |
| 账号/余额 | GET user/info；data.id/phone/balance。balance 在官方钱包页直接以元保留两位小数 |
| 扫码 | scanCodeInit 仅取 URL 的 NQT、SN、IMEI；POST goods/scan/v2 |
| 商品设备 | POST goods/normal/details（goodsId）；吹风机 categoryCode 必须为 03 |
| 老设备 | POST machine/detail（machineId）；吹风机 parentTypeId 为 4eeb1b0a-d006-49cc-bf17-73c20599057b |
| 吹风机页 | /pages/chooseDryer/newBlower/newBlower?goodsId=；选择时长后 goods/newPreview，再由服务端计算报价与交易 |
| 订单 | GET order/list?page=&pageSize=；data.items，按已确认的吹风分类过滤 |
| 官方支付宝入口 | app.js / 扫码 chunk 使用 appId=2018072460764274，page=pages/skipNew/skipNew，嵌套 query 包含 keepUsing=1 与扫码参数 |

匿名 GET user/info：普通 urllib UA 返回 405 HTML；使用官方 H5 的 Origin、Referer、iPhone WebKit UA、phoneBrand 和 Accept 后返回 HTTP 200 / code=2 / 未登录。本版原生读接口保留这一 H5 请求上下文，依然必须取得用户自己的有效 Token；没有绕过认证。

## 实现

由 new-app.ps1/SwiftUI-App 模板创建。SwiftUI 三页：吹风、订单、账号；AVFoundation 相机扫码，亦可粘贴完整二维码。扫描内容不会作为网页或外部协议打开，只解析允许的三个设备标识，拒绝重复字段、异常内容和其他机型。识别前清除上次设备；确认吹风分类后才提供使用按钮。

“去支付宝选时长并使用”经用户确认后打开官方小程序。扫码标识进入固定的小程序地址，账号 Token 不进入跳转 URL。时长、金额、真实付款、启动和倒计时由官方支付宝流程完成。本 IPA 没有实现自己的支付 SDK 或蓝牙控制，不能宣传为完全独立的原生胖乖客户端；官方小程序可能保留其自身页面内容。

账号登录保留真正的官方网页和验证码/滑块流程，不模拟验证码通过、不自动发送短信。网页仅允许登录、协议与内部空白返回路由；阻止首页营销与非登录业务路由，资源规则阻止指定广告统计域。Native API 仅允许 user/info、goods/scan/v2、goods/normal/details、machine/detail、order/list；没有下单、支付、自动充值、开会员或启停设备接口。Token 保存本机 Keychain，WebKit 登录资料留在本 App 的数据存储中；退出会清除两者。原生请求不跟随重定向，错误不反射服务器可能带隐私的 msg。

订单页只显示明确识别为吹风的记录；服务端按全账号订单分页，可能出现当前页没有吹风订单而后续页仍有的情况。未识别分类的记录不冒充吹风订单。订单是最后一次刷新结果，不伪造运行倒计时。通用余额不混入积分或受限商家余额。没有打包原 APK、原广告/推送 SDK 或提取出的业务 JS。

## 构建、验证和安装

沿用现有 project.py/ci_build.py/validate_ipa.py、公开仓库 severus-S/luckin-random 和 xcode-27 标准 runner。复用前核对公开可见性，未过期 Artifact 约 18.8MB；按本会话已核对的 GitHub 标准公开 runner 规则运行，不使用付费 runner 或新服务、不变更预算。工作流原样复用，20 分钟超时、Artifact 3 天。

本地 8 个 Swift 文件语法检查、工作区 4 项 selftest 通过；另有 16 项核心协议测试和登录路由的离线 JS 测试。最终编译与 IPA 验证结果完成后追加。

真实账号登录、支付宝唤起/返回、时长选择、付款、设备运行、安装和续签尚未验收。用户自行操作全部电脑界面与手机物理操作。本次后台只进行了文件、命令、公开脚本和匿名只读接口检查；没有发送短信、下单、支付或控制设备。

最终交付未签名 IPA，需用户使用 Sideloadly 自行签名安装；新 Bundle ID 不使用其他 App 的描述文件，编译/签名/安装/续签分别验收。

首次 Run 44766574772：Swift 包的 16 项测试中 15 项通过；末尾换行二维码被 trim 去除后接受，和“控制字符应拒绝”的输入边界不符。已将 trim 范围改为仅空白（不含换行），并给用例增加具体输入定位信息；该失败运行没有交付 IPA。

Run 44766933441 的 16 项 Swift 测试全部通过；iOS 编译时 Swift 6.4.2 在错误分支的诊断过程中断言崩溃，堆栈精确指向 HairSession.perform 的隐式 catch error 与同名属性赋值。已将属性赋值明确写为 self.error；不修改 runner/流水线，也不把编译器崩溃解释为设备兼容性问题。另增加设备标识中 +、/、= 的支持及双层跳转编码回归用例，共 17 项核心测试。Run 44767354036 由包含错误分支修正的新运行替代。


最终 Run 44767621383 / 提交 359baf1a7302a6a39f2142e114d2e760b6687912：Xcode 27.2 编译及 17 项 Swift 单测通过。本地下载核对来源、ZIP CRC、0.1.0 (1)、com.sjx13.ios.pghair、iOS17.0、arm64、AppIcon、相机用途键，无 ATS 全局例外、无 LC_CODE_SIGNATURE/签名目录/描述文件。IPA 225091 字节，SHA-256 `9b7649cc992e32e7f8348f34e23efd0bd2dfd42d5d1b7541b7f820f0d0d12cb9`。交付 artifacts/latest/PGHair/PGHair-unsigned.ipa。签名安装、登录及实际吹风流程仍待用户真机验收；付款、启动及实时状态由官方支付宝小程序处理。
登录回到的 /__pghair__ 实际匿名读取 HTTP200，返回官方 SPA 文档；离线路由测试、原生请求上下文和输入边界验证不等同于真实账号登录。
