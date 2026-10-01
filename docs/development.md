# 开发指南

## 从源码运行

需要 macOS、Xcode、Python 3、XcodeGen，以及用于真实地图体验的 iPhone 或 iPad。部署目标为 iOS 17。

在仓库根目录执行：

```sh
brew install xcodegen
python3 Scripts/fetch-sdk.py
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

编辑 `Config/Local.xcconfig`，填写高德 iOS Key。该文件已被 Git 忽略；Key 随构建写入应用配置，不在应用设置中输入。高德控制台绑定的 Bundle ID 必须与构建目标一致，默认值为 `me.mapannai.ios`。

```sh
xcodegen generate
open MapAnNai.xcodeproj
```

在 Xcode 中选择自己的签名团队和设备，运行 `MapAnNai` scheme。修改 `project.yml` 后需要重新运行 `xcodegen generate`。

SDK 由 `Scripts/fetch-sdk.py` 下载固定官方版本，无需 CocoaPods。`Vendor` 不提交；高德 `AMap.bundle` 必须作为完整资源 bundle 打包。

## 连接服务

在应用设置中填写 [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) 服务地址和 API token。地址允许带 `/api` 后缀，客户端会规范化。推荐 HTTPS，也支持局域网 HTTP。

应用不读取 `.env`；根目录 [env.example](../env.example) 仅说明配置的归属。API token 保存在 Keychain，只通过 Bearer header 发送给服务端；图片直传不携带该 token。服务端 Web 地图 Key 与原生 iOS Key 分开配置。

搜索、地点详情和路线规划通过 `ServerMapServices` 调用现有服务端 API，不使用原生搜索 SDK，也不覆盖服务端 provider。搜索加载更多需要服务端分页支持；缺少分页字段时保留第一页。

## 示例与模拟器

在 Xcode 的 Run Scheme Arguments 中添加 `--demo`，可查看只读示例旅行；退出示例需移除该参数。示例不写入服务端。

模拟器不链接高德真机 SDK，使用明确标记的交互预览画布。它适合验证面板、表单和导航，不能代替高德地图、定位、手势或流畅度的真机验证。

## 代码入口

| 目录 / 文件 | 职责 |
| --- | --- |
| `Core/AppStore.swift` | 地点、旅行、搜索与选择状态 |
| `Core/MapServices.swift` | 地图服务与配置接口 |
| `Core/MapLayout.swift` | 面板布局与地图遮挡参数 |
| `Core/RouteProcessing.swift` | 后台路线处理与空间索引准备 |
| `Map/` | 高德渲染及模拟器预览 |
| `Views/` | 旅途、搜索、地点详情与编辑界面 |
| `Tests/`、`UITests/` | 单元测试与界面测试 |

当前地图配置源固定为高德，Google renderer 尚未实现。未来配置接口需依据实际服务端合约接入，不应自行假定端点。内部与 API 坐标使用 WGS-84，高德渲染边界转换为 GCJ-02。

## 验证修改

真机目标无签名编译：

```sh
xcodebuild -project MapAnNai.xcodeproj -scheme MapAnNai \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/mapannai-build CODE_SIGNING_ALLOWED=NO build
python3 Scripts/verify-app-resources.py \
  /tmp/mapannai-build/Build/Products/Debug-iphoneos/MapAnNai.app
git diff --check
```

先查看本机可用模拟器，再选择对应名称执行测试：

```sh
xcrun simctl list devices available
```

例如已安装 iPhone 17 Pro 模拟器时：

```sh
xcodebuild -project MapAnNai.xcodeproj -scheme MapAnNai \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

服务请求测试使用 mock；真实读写验证使用独立测试后端。地图性能需通过设备体验或 Instruments 采样确认，不能用编译和模拟器测试结果代替。

产品功能见 [中文 README](../README.zh.md) / [English README](../README.md)。

## unsigned IPA 与自动发布

本地已有 `Config/Local.xcconfig` 时运行：

```sh
Scripts/build-unsigned-ipa.sh dist
```

脚本使用 Release 配置构建真机 App，检查地图资源与 Key 已嵌入，打包为 `Payload/MapAnNai.app`，输出 IPA 和 SHA256 文件。无需 Apple 签名证书。

GitHub 仓库需设置 Actions Secret `AMAP_IOS_KEY`。推送 main 或手动运行 Build unsigned IPA 工作流可下载 artifact；推送 `v0.0.1` 格式的标签会在构建成功后自动发布 Release，标签版本必须与 project.yml 的 MARKETING_VERSION 一致。发布前更新 docs/release-notes.md。只给发布任务 contents:write，构建任务只读仓库。

AltStore Classic 会以安装者的账号重新签名。它可能改变 Bundle ID，高德 Key 必须绑定最终的 Bundle ID；若遇地图鉴权失败，构建者需要为该标识配置匹配的 iOS Key 后重打包。不要在应用设置中要求使用者输入地图 Key。

## AI 助手

设置页的“AI API 配置”可填写兼容 OpenAI 的模型 API 地址、Key 和模型名。配置按 MapAnNai 服务与凭据隔离，Key 仅存钥匙串；聊天记录存设备 Application Support，不同步到 Web。

客户端只调用现有 `POST /api/ai/chat`，发送 settings/messages/context，并消费 NDJSON 的 delta、message、status、changed、complete、error 事件。系统提示词、旅行上下文补全与 MCP 工具由 MapAnNai Plus 服务器负责，iOS 不维护副本、不直连模型或执行工具。模型 API 配置会通过此请求交给用户连接的服务端。

地图右上角提供无文字的圆形 AI 图标入口，由 `AIPlannerStore.entryEnabled` 控制；本地 UI 验证可添加 `--demo --ai-planner-demo`，只读示例禁止发送规划请求。iPhone 使用原旅途 sheet 的半屏/全屏，关闭恢复原档位；iPad 宽窗口使用右侧聊天区，留出地图空间，窄窗口使用底部面板。

只从实时 create_marker / plan_trip_day 工具结果中提取 status=created 的 ID。串行合并刷新后定位新地点，不打开地点详情；历史加载、失败结果、关闭助手和失效请求不触发定位，刷新期间用户主动镜头操作优先。停止可能无法撤销服务器已执行的写入，续聊补齐未知工具结果并交由服务器查询实际数据，不自动重试规划请求。
