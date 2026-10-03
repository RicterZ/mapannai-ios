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

“打开地图”偏好保存在本机，默认系统地图，切换不重建地图或重新连接服务。高德导航使用官方 iosamap URL，传入原始 WGS-84 坐标及 dev=1；无法打开时提示用户安装或选择系统地图。

地点详情打开期间点击底图POI，详情关闭后直接交接添加页，旅途保持最小档；保存成功展示新地点详情，关闭后仍保持最小档，取消添加也不恢复旧详情。表单保存通过同步校验与写入预留后立即关闭，API和静默刷新继续在AppStore的Task执行；失败由全局提示的“继续编辑”恢复完整草稿，已创建ID保留以避免重复创建。编辑旅行/地点先更新本地，失败恢复原数据。

地图添加支持底图 POI 单击与任意位置长按；草稿打开后允许继续操作背景地图，换选位置保留笔记、封面与类型，并更新名称、地址与坐标。选中草稿位置显示临时蓝色圆头短尖气泡标记，白边与白色系统图标，默认中心为空心圆，图标跟随草稿类型更新；首次显示使用0.22秒缩放淡入，关闭使用同长缩小淡出；选点保持缩放并仅将遮挡位置移入添加页上方可见范围，减少动态效果时直接显示，关闭后移除。采用 SDK MATouchPoi 名称和坐标，转换为 WGS-84；现有 /api/places 补全地址但不替换 POI 名称。搜索期间不响应底图 POI，已有地点编辑期间不替换草稿；添加草稿可以换选，旧坐标补全结果不得覆盖新位置。单次点击在触摸开始时固定标记命中，SDK标记选中回调同步认领；已认领点击不再处理POI，避免镜头移动后的重新命中改变归属。点击重叠时已保存标记优先，其次底图 POI，最后路线；路线由SDK地图单击回调触发，提交预留350ms等待POI回调，新点击与销毁取消待提交任务。

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

## 界面动画

`Core/AppMotion.swift` 按交互场景维护动画：原生导航使用系统默认过渡，侧栏与工作区展示使用无弹跳的 smooth，标题交接使用淡入淡出，路线展开与自动滚动分别使用内容展开和滚动动画。动画尽量限定在对应视图或状态提交处，避免工作区动画传入整页列表和工具栏布局。

地点详情切换保留同一个系统sheet，内容向左翻页；固定标识的自定义detent通过UISheetPresentationController.animateChanges更新高度，封面预览使用更高档位，展开至全屏时保持全屏。减少动态效果时直接更新。

旅途 sheet 的拖动和升降由系统负责。最小档标题与展开导航的顶部区域根据 sheet 屏幕上的呈现高度连续交接，正文保持不透明，标题遮罩覆盖底部安全区；工作区不追加矩形裁剪，由系统 sheet 外轮廓与列表滚动区域管理底部显示，避免整页淡入导致文字、图标和分组背景短暂灰白，松手归档时使用 UIKit presentation layer 的位置补偿已提前提交的目标布局高度，观察仅在布局变化及短暂归档期间运行，稳定后停止。退出中的标题保留最小档区域的中心；展开导航实例与滚动身份保持稳定。现有高度、工具栏及搜索栏对齐补偿保留。外层背景材质随高度过渡至systemGroupedBackground；仅内容分组行固定systemBackground，半屏和全屏保持白色。减少动态效果时取消额外位移、旋转与缓动。高德镜头、标点缩放和路线小球保持各自的 SDK / 渲染时序。

## unsigned IPA 与自动发布

本地已有 `Config/Local.xcconfig` 时运行：

```sh
Scripts/build-unsigned-ipa.sh dist
```

脚本使用 Release 配置构建真机 App，检查地图资源与 Key 已嵌入，打包为 `Payload/MapAnNai.app`，输出 IPA 和 SHA256 文件。无需 Apple 签名证书。

GitHub 仓库需设置 Actions Secret `AMAP_IOS_KEY`。推送 main 或手动运行 Build unsigned IPA 工作流可下载 artifact；推送 `v0.0.1` 格式的标签会在构建成功后自动发布 Release，标签版本必须与 project.yml 的 MARKETING_VERSION 一致。发布前更新 docs/release-notes.md。只给发布任务 contents:write，构建任务只读仓库。

AltStore Classic 会以安装者的账号重新签名。它可能改变 Bundle ID，高德 Key 必须绑定最终的 Bundle ID；若遇地图鉴权失败，构建者需要为该标识配置匹配的 iOS Key 后重打包。不要在应用设置中要求使用者输入地图 Key。

## 图片上传排查

地点封面先在后台降采样到最长边1600并编码为82%质量JPEG，再通过带Bearer认证的`POST /api/upload`获取上传许可，使用相同的`image/jpeg`直接PUT到COS，不携带API token。成功后仅更新编辑草稿，保存地点时提交公开图片地址。

上传错误分别标明获取许可、连接图片存储与COS响应阶段。COS非2xx响应只展示HTTP状态与经过限制的XML Code，不展示原始响应、签名URL或凭据；排查签名/权限问题应使用这个错误码，不能凭“图片上传失败”推断具体原因。单元测试通过隔离的URLProtocol验证上传流程与认证边界，不操作生产存储。

## AI 助手

聊天消息采用圆角气泡与 iMessage 风格的弯曲尾巴：用户消息为右侧蓝色气泡，助手消息为左侧系统灰色气泡；尾巴不改变文字布局与选择交互。

设置页的“AI API 配置”可填写兼容 OpenAI 的模型 API 地址、Key 和模型名。配置按 MapAnNai 服务与凭据隔离，Key 仅存钥匙串；聊天记录存设备 Application Support，不同步到 Web。

客户端只调用现有 `POST /api/ai/chat`，发送 settings/messages/context，并消费 NDJSON 的 delta、message、status、changed、complete、error 事件。系统提示词、旅行上下文补全与 MCP 工具由 MapAnNai Plus 服务器负责，iOS 不维护副本、不直连模型或执行工具。模型 API 配置会通过此请求交给用户连接的服务端。

地图右上角提供无文字的圆形 AI 图标入口，由 `AIPlannerStore.entryEnabled` 控制；本地 UI 验证可添加 `--demo --ai-planner-demo`，只读示例禁止发送规划请求。iPhone 使用独立系统 sheet 的半屏/全屏，旅途页面与原档位保留；iPad 宽窗口使用带滑入/滑出动画的右侧聊天区，入口图标切换开关，不显示下拉拖动条，留出地图空间，窄窗口使用底部面板。

只从实时 create_marker / plan_trip_day 工具结果中提取 status=created 的 ID。串行合并刷新后定位新地点，不打开地点详情；历史加载、失败结果、关闭助手和失效请求不触发定位，刷新期间用户主动镜头操作优先。停止可能无法撤销服务器已执行的写入，续聊补齐未知工具结果并交由服务器查询实际数据，不自动重试规划请求。

AI配置缺失或无效时，聊天页显示“前往设置”入口并禁用发送，配置仍统一位于应用设置。

## 笔记编辑布局预览

`--demo --note-composer-preview` 打开独立原生编辑预览，预填文字和两张本地示例缩略图。正文使用 UITextView，键盘上方显示字体样式工具，地点胶囊使用当前地点。PhotosPicker 支持最多九张本地多选预览；示例入口不上传图片、不保存服务端数据。正式地点表单通过“编写笔记/编辑笔记”进入同一编辑页，自动弹出键盘；勾选保存回地点草稿，再由地点表单保存提交服务端。多图复用现有压缩与COS上传流程，先追加到笔记末尾，失败保留已成功图片并允许重选。

启动时请求系统前台定位授权并单次获取位置，地点加载后将镜头移至最近的有效已保存标记（zoom15），不弹详情。拒绝或定位失败保留日期启动视图；用户已点击、拖动、缩放地图或主动改变镜头时，不由迟到定位覆盖。周期刷新不重复定位。

底部旅途收起胶囊在 iOS 26 及以上使用原生 `glassEffect`，较早系统回退到 `regularMaterial`。材质随原生 sheet 的实际高度过渡至展开背景；搜索与 AI 工作区保持原有背景。控件按内容区加上上下安全区后的外框中心对齐，背景材质变化不改变按钮命中尺寸。胶囊背景上下各内收 2pt（总高度减少 4pt），仅改变绘制轮廓，不改变布局、安全区、元素中心或命中区域。

创建旅行的所有入口使用固定 `.medium` 原生半屏 sheet，不提供全屏档位或拖动条；编辑旅行保持原有展示方式。键盘避让由系统处理，表单可滚动。

从日详情进入搜索时，展开和收起状态的标题统一为“搜索图标”，副标题为“同时添加到今日行程”；这里的今日行程指进入搜索时冻结的目标日。旅行入口冻结旅行 ID，副标题为“同时添加到当前旅行”；总览入口仅收藏地点。

旅行级未安排地点读取 `Trip.markerIds`（旧服务缺失时按空列表处理），添加通过 `POST /api/trips/:id/markers`，body 为 `{markerId}`。旅行详情显示“未安排日期”，搜索/添加冻结目标旅行。拖入日期通过现有 `POST /api/trips/:id/days/:dayId/markers`，后端原子移除旅行级成员；本地乐观更新同时移除旅行成员，失败恢复两者。路线末尾追加使用已有日更新接口，仅更新成员/路线快照，不自动分配路线。

`--demo --trip-places-preview` 保留本地设计预览，不向服务器写入。正式模式使用真实 `Trip.markerIds`，不使用预览地点。

地点详情“加入今日行程”和日标题保存先同步更新本地状态，失败回滚。搜索添加提交后即使退出搜索，后台仍完成原目标日的保存；只在原搜索session更新结果状态。切换服务器清理保存预留，旧请求不得改写新连接的数据或写入状态。图片上传、搜索与连接测试仍等待真实结果，不用假数据代替成功。

手机添加地点草稿默认半屏，包括搜索结果加号、地图搜索标记和地图 POI/长按入口；保留上拉全屏，搜索框开始输入时仍可展开。iPad 固定居中表单保持原样。

地点行拖动使用系统拖动预览，保留原行尺寸/样式，提起与放下提供轻触觉反馈。当天孤立点可拖入路线任意可见行：插入顺序以系统预留的让位空隙为准，标题追加末尾；原生 UICollectionView 提供让位及落点动画，使用拖动起始行索引映射系统落点，避免预览空隙与实际顺序偏移。不绘制额外蓝色插入标识线。路线地点滑动删除及“移出路线”菜单保留当天成员，清理当天路线引用后回到未规划地点区域；未规划地点的删除仍从当天移除。

旅途进入搜索在同一工作区内以 0.22 秒淡入淡出切换，不从底部滑入。进入时保持当前半屏/全屏，仅胶囊入口展开至半屏；退出仍恢复进入前档位、导航和滚动状态。添加草稿默认半屏行为不变。

日详情始终显示灰色小标题“未收入路线”，独立地点与添加地点入口共用分组。路线地点支持原生长按拖动排序、跨路线移动，拖到未收入路线区域清理路线引用并保留当天成员；路线编辑菜单保留在路线标题。

应用内地点拖放在松手回调中同步读取本地载荷并立即提交列表变化，不等待 NSItemProvider 异步加载或落点动画结束；路线几何与距离继续后台计算并补全。

路线内向下拖动将 UIKit 移除源行后的最终索引转换为模型插入边界，只扣除一次原位置。拖放预览独立落点，不用会隐藏目标单元格的 toItemAt；拖放提交不叠加 SwiftUI 列表动画，路线距离继续后台补全。未收入路线落点按当前可见区域识别，支持列表滚动后放入。

系统可能将地点的自定义 NSItemProvider 包装为 UIItemProvider；本地载荷通过 suggestedName 随包装保留，落下时同步读取，不能依赖子类类型判断。路线展示行身份同时包含地点 ID 与本地位置，换位后重新绑定内容及序号，接口仅持久化本地顺序。离线交互回归检查 2→3 换位后的唯一地点行与连续标号。

路线标号由独立观察 AppStore 的地点按钮直接读取本地 chains 顺序，不使用父行捕获的位置，也不依赖 displayRoutes/距离补全。DEBUG 参数 --delayed-route-build-preview 将路线构建延迟 8 秒，用于验证标号先于几何更新；只在只读示例中生效。

被拖起的路线地点保留系统原生截图预览，不在窗口叠加独立标号，不在拖动期间重设 previewProvider。浮动截图保留提起时的标号；落下后的实际列表读取本地顺序更新标号。
