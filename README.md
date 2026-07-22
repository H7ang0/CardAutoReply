# CardAutoReply — 抖音私信「自动回复卡片」

**收到对方私信时，按规则自动回复一张链接卡片**。完全用抖音**原生类**收发。

<p align="center">
  <img src="screenshots/settings.png" width="270" alt="设置页">
  &nbsp;&nbsp;
  <img src="screenshots/edit.png" width="270" alt="卡片编辑页（带实时预览）">
</p>

- 关键词命中优先，未命中走「默认卡片」（关键词留空的规则），支持**精准 / 模糊**匹配
- 多条规则，每条独立配置：关键词 / 封面URL / 标题 / 描述 / 跳转链接
- **每会话冷却 N 分钟**，防刷屏、避风控
- **全局触发**：hook TIMX SDK 全局单例 `TIMXOThirdPartyConversationNotifier`，任何会话来消息都能自动回，不用打开聊天页
- 发送走抖音 IM SDK：`IESIMSendMessageModel`(messageType=26 链接卡片) + `IESIMMessageSender`
- iOS 26 液态玻璃设置页，卡片编辑带实时预览

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

1. **卡片发出但显示红叹号 / 发送失败** → `AHRSendCard()` 用 `IESIMSendMessageModel`(messageType=26,
   content={cover_url,title,desc,link_url}) + `IESIMMessageSender asyncSendMessage:completion:`。
   看日志 `[CardAutoReply] ❌ 发送失败: …` 里的错误(风控 / conversationId / 缺字段)。
2. **自己发消息也被触发** → 方向判断用 `TIMXOMessage.sender == currentUserID`。当前 uid 从
   `TIMXOThirdPartyConversationNotifier._r`(TIMXSDKInstance) 取，取不到时不拦、靠冷却兜底。
3. **关键词匹配不到 / 文本不对** → `AHRTIMXText()` 从 `TIMXOMessage.content` 取（默认 `content[@"text"]`，
   带兜底扫描）。日志打印 `content=…` 校准键名。
4. **「+」面板里没出现「自动回复卡片」项** → 确认 `AWEIMPlusPanelView` / `AWEIMChatPanelModel`
   类名未变；日志无异常即应显示在九宫格末尾。

排查时看设备日志里 `[CardAutoReply]` 前缀的输出。

## 说明 / 边界

- **全局触发**：hook TIMX SDK 全局单例 `TIMXOThirdPartyConversationNotifier -didInsertNewMessages:belongingConversation:`，
  所有会话新消息都触发，不用打开聊天页。
- **iOS 限制**：越狱插件寄生在抖音进程内，抖音被系统**挂起 / 杀死**时插件不运行，无法自动回。只在抖音**运行时**（前台或短暂后台）有效。
- 卡片内容里 `封面URL`/`链接` 建议用公网 https 直链。
- 冷却记录存在 `NSUserDefaults`（`AHRCardAutoReply.lastSend`），跨重启保留。
