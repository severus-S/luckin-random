# 签名安装与续签

成功构建的产物是未签名 IPA。用户使用自己可信的本机 Sideloadly 环境完成签名安装；Apple ID 密码和二次验证码仅在本机可信界面输入。

1. 下载指定成功运行并核对 manifest、commit、SHA256 和 Bundle ID。
2. 在 Sideloadly 选择自己的 iPhone，把 LuckinRandom-unsigned.ipa 拖入，使用自己的 Apple ID 完成签名和安装。
3. 手机按实际提示信任开发者、开启开发者模式并启动 App，先走离线模拟。
4. 配置真实服务时，在手机设置页填写 HTTPS 后端与配对密钥，再在手机填写官方 MCP Token。
5. 后续保持同一签名身份/有效 Bundle ID 覆盖更新；不要先卸载。重要咖啡池先导出备份。

免费 Apple ID 的签名、App 数量与周期配额以 Apple/Sideloadly 当次响应为准。到期前使用现有可靠方式刷新并检查结果；不能仅凭托盘图标声称无人值守续签通过。
所有电脑界面和手机物理操作由用户本人完成。构建成功、工具安装提示、真机运行和数据保持均分别记录。
