# 构建与安装

想在 Mac 上体验图鉴，可以从模拟器开始。想在自己的 iPhone 上扫描游戏画面，使用 Xcode 选好开发团队后直接运行到手机。

| 项目 | 1.5 的设置 |
| --- | --- |
| 运行设备 | iPhone，最低部署版本为 iOS 27.0。iPhone Duo 在 iOS 27.1 及以上还会读取系统的铰链状态。 |
| 已验证的构建环境 | Xcode 27.2，iOS 27.2 SDK。编译需要包含 `UIHingeInteraction` 的 SDK。 |
| 工程与方案 | `RocoDex.xcodeproj`，共享方案 `RocoDex` |
| 版本 | 1.5，构建号 6 |
| 发行版 Bundle ID | `com.feiyang.rocofieldguide` |

## 在模拟器打开

1. 下载 [v1.5.0 源码](https://github.com/liudbhx7-bot/roco-world-duo-dex/archive/refs/tags/v1.5.0.zip) 并解压，双击 `RocoDex.xcodeproj`。
2. 在 Xcode 顶部选中 **RocoDex** 方案，再选 **iPhone Duo** 模拟器。如果设备列表缺少该机型，在 Xcode 的 Settings → Components 安装对应的 iOS 模拟器运行时，再创建或选择该机型。
3. 按 **⌘R** 运行。点「查编号」，输入 `008` 查看水蓝蓝。测试相册识别时，可先将工程内的 `RocoDex/Resources/Art/008.png` 拖进模拟器，再在图鉴中点「扫描」→「从相册识别」。

工程随附立绘、地图、识别索引与 665 条音轨。打开工程即可编译，配音模型只在制作音轨时使用。

## 安装到自己的 iPhone

1. 在 Xcode 的 Settings 中找到 Apple 账户设置并登录。用数据线连接已解锁的手机，按系统提示信任这台 Mac。若设备要求开发者模式，按提示启用。[Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
2. 在工程导航栏选中 **RocoDex** 工程，进入 **Targets → RocoDex → Signing & Capabilities**。勾选 **Automatically manage signing**，将 **Team** 改为你自己的团队。首次自行构建时，如果 Xcode 提示原 Bundle ID 已被占用，换为你团队可注册的唯一标识。
3. 在 Xcode 顶部将运行目标选为这台 iPhone，保持手机解锁并按 **⌘R**。首次点击「扫描」时，允许图鉴使用后置相机。[Apple 真机与模拟器运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)

**更新已有安装**时，沿用原安装的 Bundle ID 和可覆盖它的签名身份，保留手机上的旧版并执行覆盖安装。发现记录保存在原应用的数据容器里。更换 Bundle ID 会装成独立应用，从新的记录开始。

[1.5 发布页](https://github.com/liudbhx7-bot/roco-world-duo-dex/releases/tag/v1.5.0) 也提供 `RocoDex-1.5-unsigned.ipa`。这个附件需要先配置适用于自己的 Apple 签名和设备的描述文件，再安装到手机。模拟器请使用上面的源码构建流程。

## 运行测试

在 Xcode 中选好模拟器，按 **⌘U** 即可运行方案中的测试。也可以从工程根目录运行核心测试，先用下面的命令列出本机可用目标。

```sh
xcodebuild -project RocoDex.xcodeproj -scheme RocoDex -showdestinations
```

把命令中的占位符替换为上一步列出的 iOS Simulator 设备 ID。

```sh
xcodebuild test -project RocoDex.xcodeproj -scheme RocoDex \
  -destination 'platform=iOS Simulator,id=<模拟器设备 ID>' \
  -only-testing:RocoDexTests
```

界面测试中有三项需要先向模拟器相册导入指定图片，并为对应测试启用环境变量。测试文件逐项注明了所需的水蓝蓝、铃兰夫人或纯色图片。缺少指定环境变量时，相应测试会跳过。[界面测试与素材条件](../RocoDexUITests/FieldGuideUITests.swift)

修改立绘或头像后，从工程根目录运行 `sh Tools/rebuild-scan-index.sh`，随改动一起提交新索引。补充 APNG 或替换介绍配音时，按应用形态 ID 命名，同号形态使用各自的资源文件。[素材命名与替换步骤](../使用说明.md#补充动图或真人录音)
