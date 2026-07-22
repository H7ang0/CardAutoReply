# CardAutoReply — 抖音私信「自动回复卡片」

**收到对方私信时，按规则自动回复一张链接卡片**。完全用抖音**原生类**收发，不依赖任何第三方 dylib。

- 关键词命中优先，未命中走「默认卡片」（关键词留空的规则）
- 多条规则，每条独立配置：关键词 / 封面URL / 标题 / 描述 / 跳转链接
- **每会话冷却 N 分钟**，防刷屏、避风控
- 卡片 = 抖音自带 `AWEIMShareH5Message`（`title`/`coverURL`/`desc`/`linkURL`/`isCard`），
  经 `AWEIMSendMessageController` 发送；方向判断用官方 `AWEIMMessage.sendFromMe`

> ⚠️ **不能与 DouyinHelper 同时安装**（同进程 hook 冲突）。本模块自带收发与设置入口，独立运行。

## 文件

| 文件 | 作用 |
|---|---|
| `Tweak.xm` | hook 收私信 + 匹配/冷却/发送逻辑、存储 `AHRStore` |
| `Editor.mm` | 设置界面 `AHRCardAutoReplyEditor`（`+present` 呼出） |
| `PanelIntegration.xm` | 把入口做成聊天「+」面板(`AWEIMPlusPanelView`)里的一个九宫格项 |
| `Makefile` / `control` / `CardAutoReply.plist` | Theos 构建（注入进程 `Aweme`，按类 `AWEIMMessageListDataComponent` 过滤） |

## 编译

需要 [Theos](https://theos.dev)（已装在 `~/theos`）。**用附带的 `build.sh`**（它会自动设好
`THEOS` 和 `DEVELOPER_DIR`——后者是为绕过 Xcode 16/26 上 `xcodebuild -sdk '' -find make` 崩溃的坑）：

```bash
cd CardAutoReply
./build.sh                  # 只编译
./build.sh package          # 打 rootful .deb  -> ./packages/
./build.sh package rootless # 打 rootless .deb（TrollStore/Dopamine 等新越狱）
./build.sh clean
```

> 若你坚持直接用 `make`，必须先在**当前 shell 环境**里设两个变量（写进 Makefile 无效）：
> `export THEOS=~/theos DEVELOPER_DIR=/Library/Developer/CommandLineTools`

产物已验证可正常编译/打包（arm64 + arm64e）。装到设备：把 `./packages/*.deb` 用
Filza / `dpkg -i` / 包管理器安装，或 `./build.sh package install`（需配 `THEOS_DEVICE_IP`）。

> 本模块是**独立 dylib**，注入抖音进程后用抖音自己的类收发消息，不依赖任何第三方 dylib。

## 使用

1. 进入任意私信会话，点输入框左/右的 **「+」** 展开面板，九宫格里点 **「自动回复卡片」** 进入设置页
2. 打开「启用自动回复卡片」
3. 「+」添加规则，填关键词与卡片内容；**关键词留空的那条 = 默认卡片**
4. 设「每会话冷却(分钟)」，默认 5
5. 对方发消息命中规则即自动回卡片

## ⚠️ 上机核对清单（代码已编译通过，但收发是抖音私有流程，装机后确认这几点）

1. **卡片发出但不渲染 / 发送失败** → `AHRSendCard()` 用 `AWEIMShareH5Message` + `AWEIMSendMessageController`。
   若不渲染：可能要改用该类的 `initWithContentDict:`（按抖音的 content 键构造）而非 typed 属性；
   若发送失败：`sendMessage:conversation:` 的会话参数换 `conv`（现传 `conv.con`）试。看日志
   `[CardAutoReply] 已发送卡片(原生)` 是否出现。
2. **自己发消息也被触发** → 方向判断用官方 `AWEIMMessage.sendFromMe`（已确证存在）。若仍误触，
   日志打印 `didReceiveNewMessage:` 传入对象的类核对。
3. **关键词匹配不到** → `AHRMessageText()` 没取到文本。打印传入对象 `-description`，
   看文本字段在哪（`attributedContent` / `rawContentDict[@"text"]`），按需补。
4. **「+」面板里没出现「自动回复卡片」项** → 确认 `AWEIMPlusPanelView` / `AWEIMChatPanelModel`
   类名未变；日志无异常即应显示在九宫格末尾。

排查时看设备日志里 `[CardAutoReply]` 前缀的输出。

## 说明 / 边界

- 只在**聊天页处于打开状态**收到消息时触发（hook 的是聊天页数据组件）。后台/列表页到达的消息不触发——
  若要后台也自动回，需要 hook 更底层的消息接收（TIMX/IES 层），可在此基础上扩展。
- 卡片内容里 `封面URL`/`链接` 建议用 https 直链。
- 冷却记录存在 `NSUserDefaults`（`AHRCardAutoReply.lastSend`），跨重启保留。
