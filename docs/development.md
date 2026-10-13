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

添加地点、附近地点及搜索结果复用同一个地图面板和 NavigationStack。进入时按当前地图中心30公里列出已保存地点，按距离排序；清空关键词恢复附近列表。手机下拉至80pt内容区（24pt拖动区+56pt搜索行，外层另计底部安全区）仅保留输入框，不退出搜索、不清空关键词或结果，点返回才恢复之前旅途；输入时恢复半屏。键盘出现时面板背景展开并延伸到屏幕底部，内容由SwiftUI键盘安全区避让，不把面板底边截在键盘顶部，避免键盘圆角和材质露出地图；键盘收起恢复原档位。地点预览与添加草稿在同一容器内导航。地图点选从半屏或全屏进入地点详情时记住原档位，详情显示半屏，关闭后动画恢复原档位；退出添加地点时旅途面板动画恢复，只有首次进入全屏日详情省略面板呈现动画。搜索结果仅在列表中展示，加载与翻页不移动地图镜头；点选后地图只显示当前结果，以暖黑色名称标签、细连接线和白边小圆落点突出显示，不使用行程序号。三个地图底图共用标记样式，原有行程标记和路线保留。

搜索与 Web 的 mergeSearchResults 使用相同合并规则：已加载地点的标题全局匹配并优先显示，POI 仍按冻结的视口范围分页请求 /api/search。坐标按六位小数匹配已有地点，结果携带本地 markerId 以复用地点及其内容；跨页去重保留独立的地点与 POI 身份。POI 请求失败时保留已匹配的收藏地点。

已收藏搜索结果显示原地点图标与“已收藏”。搜索期间点击地图标记或列表正文只选择并打开地点预览，不隐式加入行程；预览中的加入按钮与列表加号才按入口层级加入目标日成员或旅行未安排地点，总览入口查看已收藏地点。普通 POI 的明确添加操作进入添加草稿。地图长按的临时搜索结果立即显示 POI 名称或“地图选点”和坐标，异步补全名称与地址；取消草稿保留有效结果，退出或更换搜索会话后丢弃旧补全结果。

“打开地图”偏好保存在本机，默认系统地图，切换不重建地图或重新连接服务。高德导航使用官方 iosamap URL，传入原始 WGS-84 坐标及 dev=1；无法打开时提示用户安装或选择系统地图。

地点详情打开期间点击底图POI，详情关闭后直接交接添加页，旅途保持最小档；保存成功展示新地点详情，关闭后仍保持最小档，取消添加也不恢复旧详情。表单保存通过同步校验与写入预留后立即关闭，API和静默刷新继续在AppStore的Task执行；失败由全局提示的“继续编辑”恢复完整草稿，已创建ID保留以避免重复创建。编辑旅行/地点先更新本地，失败恢复原数据。

地图添加支持底图 POI 单击与任意位置长按；草稿打开后允许继续操作背景地图，换选位置保留笔记、封面与类型，并更新名称、地址与坐标。选中草稿位置显示临时蓝色圆头短尖气泡标记，白边与白色系统图标，默认中心为空心圆，图标跟随草稿类型更新；首次显示使用0.22秒缩放淡入，关闭使用同长缩小淡出；选点保持缩放并仅将遮挡位置移入添加页上方可见范围，减少动态效果时直接显示，关闭后移除。采用 SDK MATouchPoi 名称和坐标，转换为 WGS-84；现有 /api/places 补全地址但不替换 POI 名称。搜索期间不响应底图 POI，已有地点编辑期间不替换草稿；添加草稿可以换选，旧坐标补全结果不得覆盖新位置。单次点击在触摸开始时固定标记命中，SDK标记选中回调同步认领；已认领点击不再处理POI，避免镜头移动后的重新命中改变归属。点击重叠时已保存标记优先，其次底图 POI，最后路线；路线由SDK地图单击回调触发，提交预留350ms等待POI回调，新点击与销毁取消待提交任务。

## 交通与游览安排

TripDay 解码可选 routeChains，使用稳定路线 ID、stops 访问 ID 与相邻 legs；旧服务缺失字段时保留现有距离展示。天详情使用白色路线分组、空心序号节点与细线表示访问顺序。地点标题左侧复用分类SVG，最多两行尾部省略；地址在标题下单行省略，长按复制完整原文。右侧到达时间与名称使用相同字号及顶部对齐，停留时长用次要色；单行名称时地址和停留时间对齐，两行名称不下移时间组。辅助功能字号时将时间放入主列。照片与游览备注在标题块下方占满节点右侧宽度，长备注支持展开/收起。交通使用中性浅灰底，复用已有交通SVG（无对应素材时用系统符号），方式/车次、出发时间/计划时长/有效距离分层排列；备注可展开/收起，长按打开交通编辑，不显示编辑图标。交通与游览编辑共用 `RouteScheduleEditor`：整页 `systemBackground` 白底，不使用灰色表单底和独立卡片；起终点横向紧凑显示，交通方式用两行五列直接点选，选择仅使用中性淡灰底，辅助功能大字改为两列。车次、时间与备注用细分隔线组织，底部复用 `JourneyEditorSubmit` 的白底版本固定“保存安排”，游览安排隐藏交通专属控件。保留当地时间、不填即空、清除与取消不保存的现有合约。装饰线不参与点击或拖放，实际序号仍直接订阅本地顺序。天详情顶部只显示日期切换和关闭/收起入口，正文显示可空主题及地点/路线数，不重复旅行名或日期。线路/车次号单独使用 serviceNumber；时间按行程当地 HH:mm 存储，durationMinutes 为用户计划分钟数。

保存调用 PATCH /api/trips/:id/days/:dayId/chains/:chainId，仅发送 stops 或 legs 元数据，空字段显式 null，清除交通使用 remove=true。服务端返回完整 TripDay 后立即更新本地；交通方式变化时按新的有向边重新匹配规划缓存并请求缺失路线，仅修改时间/备注不重新寻路。提交前校验路线快照，切换服务器拒绝旧结果。拖动松手同步更新 chains、访问及有向边；同路线中仍按原方向相邻的边生效，断开的边存入 inactiveLegs，恢复原方向相邻时重新生效。跨路线产生新访问，不继承游览安排；移出路线清理涉及该访问的边。计划时间不自动重排。单路线排序使用稳定 chainId PATCH，其他变更使用现有整日 PUT；对服务端旧接口无法明确安排归属的移动在提交前拒绝，避免错配。服务响应的访问 ID 直接提交，不等待刷新。所有当天地点拖动共用落点解析，孤立点拖入、路线内排序和跨路线移动不按来源区分命中规则；使用拖动开始时冻结的行中线，地点、交通块、行间空隙和卡片左右留白均接受。悬停与松手使用同一解析器；未收入路线区域保留拖动开始时的命中范围并跟随滚动补偿，避免系统插入占位推开容器后松手落错路线。地点拖动使用系统完整行预览，保留原样式及尺寸；松手后短暂屏蔽点击以防误开表单。

旅途页未加入日期地点拖放时，目标日期使用系统列表底色高亮与默认动画，进入或切换目标触发原生 selection 触觉反馈；离开、取消和松手清除高亮，减少动态效果时禁用附加动画。日期命中使用当前可见位置，随滚动更新。

只读设计预览参数 --demo --trip-places-preview --transport-schedule-preview 展示地铁、车次、时间与备注；不写入生产数据。

## 旅途卡片内容

每日内容使用连续篇章，不显示独立卡片底色与分隔线；保留原生 List 的点击、长按菜单、右滑编辑和拖放目标高亮，日期移除左滑删除入口。日序以两位数字显示，无障碍读作第N天；日期为 M月d日·周X，按行程日期计算，不随设备时区偏移。日期行右侧独立44pt省略号菜单、篇章长按与右滑编辑共用当天编辑页；正文点击仍进入当天。编辑页使用白底连续章节、日序/日期、可空主题输入和旅途已有地点多选，无独立Form卡片。地点候选为旅行未安排成员及所有日期成员/路线地点的去重并集，不提供外部搜索；无地点仍可提交。编辑保留未改路线与安排，删除成员清理路线引用，新成员按现有默认路线规则加入；外部日期变更拒绝覆盖。添加一天先弹编辑页，UTC计算现有结束日期/最后日期的次日；AppStore同步预留写入并乐观插入临时日，关闭编辑页，后台POST现有days接口发送date/title/markerIds，再PUT旅行endDate。创建接口不接受chains，新日所选地点先作为未编排成员。临时日不允许打开，获得真实ID后替换；请求失败回滚并保留草稿供继续编辑，POST已成功但endDate失败时保留真实日期和ID，重试不重复POST。连接切换清理草稿与预留，旧结果不发布。删除旅行/日期共用白底紧凑确认页，左对齐标题与说明、独占地点圆形勾选及并排胶囊按钮，默认不选且共享地点保留，点击确认立即关闭并后台删除。日主题为空或重复日期/第N天时直接省略，不生成主题或预留标题高度。现有地点封面以2.2:1横幅居中裁切，8pt圆角，下方显示对应地点名；无封面不占位。有图预留图片与图注空间，加载不改变行高。每日路线摘要改为小空心节点与细竖线，最多预览两条独立路线、每条前三站，其余明确标注还有N站/路线，不跨路线连接。未编排成员单独用caption“未编排·N个地点”显示，不再把“另有N个地点”混入正文；纯未编排日期显示中点分隔名称，无有序连线，辅助功能字号允许完整换行。底部仅显示地点数与首站时间/时间安排数，不再显示交通摘要；交通安排仍在当天详情查看。时间来自实际首站的startTime，首站未填写时统计地点游览与有效相邻交通段已有时间/正时长，每个访问或交通段最多计1项；无安排固定显示0项时间安排，不读取inactiveLegs。照片按路线和成员顺序稳定选择已有地点封面，以图片URL在同一旅行内去重；封面优先，其后按日期及ID排序依次分配，每天跳过先前已使用图片，没有新图片就省略。分配不依赖滚动或下载完成顺序，不跨旅行排除，不进行图像内容识别。

照片由独立 actor 下载、降采样并缓存；首页、详情头卡和 UIKit 转场快照共用已解码 UIImage。旅途打开期间不更新首页图片，转场完成后才加载每日横幅照片，并预留照片内容高度。保留现有转场状态、坐标、时长、层叠与手势。外层遮罩只维持顶部标题边界，底部覆盖系统安全区，让首页与每日列表自然滚出屏幕边缘。

只读样式预览使用 `--demo --archive-preview --transport-schedule-preview --journey-card-style-preview`；照片从开发机 localhost:8766 提供，不打包库存照片，不修改真实行程。

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

服务 provider 元数据的配置源固定为高德；客户端底图可选择高德或系统地图（Apple MapKit），Google renderer 通过官方 GoogleMaps Swift Package（固定11.2.0）接入。未来配置接口需依据实际服务端合约接入，不应自行假定端点。内部与 API 坐标使用 WGS-84，高德渲染边界转换为 GCJ-02。

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

地点详情切换保留同一个贴边面板，内容向左翻页；默认半屏，用户上拉全屏后切换地点保持全屏，笔记或封面更新不改变用户档位。下拉至最小档关闭并恢复之前的行程。减少动态效果时直接更新。

iPhone 旅途、搜索和日期移动／复制选择器使用贴边面板：左右及底部占满，只有顶部圆角，提供拖动条、半屏／全屏及旅途80pt收起档。UIKit presentation controller 管理外框、拖动与键盘避让，SwiftUI 保留 NavigationStack、列表和编辑控件；背景地图可交互，日期选择器遮暗背景。iPad 侧栏和居中弹窗保持原布局。减少动态效果时取消额外缓动。

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

## 设置页

设置页沿用系统sheet与NavigationStack，标题“设置”。内容使用systemBackground白底、无嵌套卡片的连续设置行、细分隔线与22pt分组标题，按地图与路线、服务连接、隐私、关于排列；iPad最大560pt居中。地图/导航使用菜单，路线开关即时保存；服务地址与访问凭据带独立标签，黑色胶囊保存并测试连接，右上角勾选保存并关闭。高德隐私默认不自动同意，保留隐私政策、项目链接及MIT许可。

## AI 助手

AI界面等待重新设计，当前地图入口关闭（`AIPlannerStore.entryEnabled = false`），设置页暂不展示AI配置或隐藏入口开关。现有配置、会话和模块保留，以下为保留模块的内部行为。

聊天滚动在消息实际布局尺寸变化后对齐底部，覆盖流式 Markdown 增高、临时回复转为正式消息与生成状态行消失；消息区使用确定高度的 VStack，避免懒加载估算高度导致完成后跳位。`--demo --ai-chat-preview --ai-stream-preview` 可只读验证长回复生成与完成。

聊天消息采用圆角气泡与 iMessage 风格的弯曲尾巴：用户消息为右侧蓝色气泡，助手消息为左侧系统灰色气泡；尾巴不改变文字布局与选择交互。

保留的AI配置组件可填写兼容 OpenAI 的模型 API 地址、Key 和模型名。配置按 MapAnNai 服务与凭据隔离，Key 仅存钥匙串；聊天记录存设备 Application Support，不同步到 Web。

客户端只调用现有 `POST /api/ai/chat`，发送 settings/messages/context，并消费 NDJSON 的 delta、message、status、changed、complete、error 事件。系统提示词、旅行上下文补全与 MCP 工具由 MapAnNai Plus 服务器负责，iOS 不维护副本、不直连模型或执行工具。模型 API 配置会通过此请求交给用户连接的服务端。

原地图圆形 AI 图标入口由 `AIPlannerStore.entryEnabled` 控制，目前关闭；本地 UI 验证可添加 `--demo --ai-planner-demo`，只读示例禁止发送规划请求。iPhone 使用独立系统 sheet 的半屏/全屏，旅途页面与原档位保留；iPad 宽窗口使用带滑入/滑出动画的右侧聊天区，入口图标切换开关，不显示下拉拖动条，留出地图空间，窄窗口使用底部面板。

只从实时 create_marker / plan_trip_day 工具结果中提取 status=created 的 ID。串行合并刷新后定位新地点，不打开地点详情；历史加载、失败结果、关闭助手和失效请求不触发定位，刷新期间用户主动镜头操作优先。停止可能无法撤销服务器已执行的写入，续聊补齐未知工具结果并交由服务器查询实际数据，不自动重试规划请求。

AI配置缺失或无效时，聊天页显示“前往设置”入口并禁用发送，配置组件仍保留，当前设置页不展示。

## 笔记编辑布局预览

`--demo --note-composer-preview` 打开独立原生编辑预览，预填文字和两张本地示例缩略图。正文使用 UITextView，键盘上方显示字体样式工具，地点胶囊使用当前地点。PhotosPicker 支持最多九张本地多选预览；示例入口不上传图片、不保存服务端数据。正式地点表单通过“编写笔记/编辑笔记”进入同一编辑页，自动弹出键盘；勾选保存回地点草稿，再由地点表单保存提交服务端。多图复用现有压缩与COS上传流程，先追加到笔记末尾，失败保留已成功图片并允许重选。

启动时单次获取系统位置，等待行程启动选择完成；仅当没有行程镜头时使用真实GPS位置（zoom12），不再跳到最近的收藏地点。用户操作和已有镜头优先，迟到定位不覆盖，周期刷新不重复定位。从旅途／日详情右上角进入地图时保留所选日期，旅途面板保持80pt收起档，不自动弹出半屏日详情。主动进入旅行地图适配全部日期及未安排地点，进入日期地图适配当天全部有效地点；即便之前已选中该日期也执行镜头更新。单点旅行zoom12、单点日期zoom15，多点使用renderer按实际地点范围与面板遮挡适配；focus=false保持镜头。空行程尚无目的地区域可定位，保留现有视野。

手机地图操作采用右下方白色组合工具条，定位／搜索使用中性19pt图形、44pt命中区域，中间用短细线分隔。工具条随旅途档位避让，展开全屏或打开搜索时隐藏。旅途面板用×收起，收起栏左对齐日期／旅行名、右侧×关闭地图，没有返回箭头；日详情用无厚重圆底的×关闭，保留原导航路径。地点详情用名称右侧×关闭，编辑入口在内容底部；背景为白色。iPad 保留侧栏导航。

创建与编辑旅途统一使用全屏表单，编辑复用名称、图标与日期范围控件。键盘避让由系统处理，表单可滚动。

日详情的搜索弹窗冻结目标日，显示“添加到今日行程”；旅行入口冻结旅行 ID，显示“添加到当前旅行”；总览入口仅收藏地点。

旅行级未安排地点读取 `Trip.markerIds`（旧服务缺失时按空列表处理），添加通过 `POST /api/trips/:id/markers`，body 为 `{markerId}`。旅行详情显示“未安排日期”，搜索/添加冻结目标旅行。加入日期通过现有日更新接口同时提交成员与默认路线，后端原子移除旅行级成员；本地乐观更新同时移除旅行成员，失败恢复两者。当天0条路线时首次添加建立路线1，1条路线时追加其中，2条及以上只加入当天的“未安排”；已有地点的重复加入保留原位置。搜索、地图添加、详情加入和跨日移动／复制使用同一默认规则。

`--demo --trip-places-preview` 保留本地设计预览，不向服务器写入。正式模式使用真实 `Trip.markerIds`，不使用预览地点。

地点详情“加入今日行程”和日标题保存先同步更新本地状态，失败回滚。搜索添加提交后即使退出搜索，后台仍完成原目标日的保存；只在原搜索session更新结果状态。切换服务器清理保存预留，旧请求不得改写新连接的数据或写入状态。图片上传、搜索与连接测试仍等待真实结果，不用假数据代替成功。

手机添加地点草稿默认半屏，包括搜索结果加号、地图搜索标记和地图 POI/长按入口；保留上拉全屏，搜索框开始输入时仍可展开。iPad 固定居中表单保持原样。

地点行拖动使用系统拖动预览，保留原行尺寸/样式，提起与放下沿用系统拖动反馈，不叠加手动 impact；实际换位时使用一次 medium impact 反馈。当天孤立点可拖入路线任意可见行：固定行中线决定插入顺序，标题追加末尾；共享组件根据同一边界执行让位和松手提交，避免预览空隙与实际顺序偏移。不绘制额外蓝色插入标识线。右滑地点显示移动、复制与删除，禁用全滑自动执行；左滑保留删除入口。删除需确认，只移除当天成员和当天全部路线引用，保留收藏及其他日期。

搜索使用独立贴边面板，提供半屏／全屏档位和拖动条；地图入口保留可交互的背景地图，旅途入口在原页面上弹出。顶部返回／输入／清除共用单层白底输入行，下方显示白底plain地点结果；退出恢复原旅途导航和档位。添加草稿在弹窗内同一NavigationStack进入，取消保留关键词和结果。首页搜索点选结果时先关闭搜索弹窗，再由onDismiss交接地图；返回后在地图关闭回调恢复搜索，不用延时串联弹窗。

日详情将未归属路线的成员归入“未安排”，无成员时不显示空分组。长按地点或路线标题直接进入当前页编辑模式，不切换页面；原生圆形多选与排序手柄用于选择／排序，底部显示全选、完成和批量移动／复制／删除。排序即时乐观保存，失败恢复；完成退出编辑模式。编辑状态保留路线间拖放，拖到未安排区域仅清理路线引用。新建路线仍使用独立编辑页；路线删除在标题左滑入口确认。移动／复制弹窗选择旅途内其他日期，复制复用地点ID并保留源日期；移动先写目标再写源，失败读取源状态后补偿目标，补偿失败明确提示并刷新，不隐藏部分成功。

应用内地点拖放在松手回调中同步读取本地载荷并立即提交列表变化，不等待 NSItemProvider 异步加载或落点动画结束；路线几何与距离继续后台计算并补全。

路线内向下拖动按冻结行中线得到模型插入边界，只在模型移除源行时扣除一次原位置。日期地点松手直接提交真实行，不追加旧截图的落点动画，也不用会隐藏目标单元格的 toItemAt；拖放提交不叠加 SwiftUI 列表动画，路线距离继续后台补全。未收入路线落点按当前可见区域识别，支持列表滚动后放入。

系统可能将地点的自定义 NSItemProvider 包装为 UIItemProvider；本地载荷通过 suggestedName 随包装保留，落下时同步读取，不能依赖子类类型判断。路线展示行身份同时包含地点 ID 与本地位置，换位后重新绑定内容及序号，接口仅持久化本地顺序。离线交互回归检查 2→3 换位后的唯一地点行与连续标号。

路线标号使用 UILabel 直接订阅 AppStore.$trips 的本地 chains 顺序，保留中的源单元格也会同步更新；不使用父行捕获的位置，不依赖 displayRoutes/距离补全。DEBUG 参数 --delayed-route-build-preview 将路线构建延迟 8 秒，用于验证标号先于几何更新；只在只读示例中生效。

被拖起的路线地点保留系统原生截图预览，不在窗口叠加独立标号，不在拖动期间重设 previewProvider。浮动截图保留提起时的标号；落下后的实际列表读取本地顺序更新标号。

拖放测试使用 --delayed-route-build-preview --delayed-route-distance-preview，将示例路线与 850 m 距离延后 8 秒发布；松手先断言真实 UILabel 为新标号且距离未出现，并保存屏幕截图。

AI 回复的管道 Markdown 表格使用原生 SwiftUI Layout 与横向 ScrollView；支持表头、对齐标记、转义竖线与流式缺失单元格，代码围栏不解析成表格。正文与单元格保留内联 Markdown，系统动态字体与文本选择继续可用。表格视口固定为气泡内容宽度，列按单元格自然宽度展开，不因气泡宽度自动折行；溢出仅在表格内部横向滚动。列宽取整列最大自然宽度，单元格底色和边框填满统一列宽与行高，交替行底色连续铺满整行。

AI 请求开始时使用 UIApplication.beginBackgroundTask 申请有限后台执行时间，结束、停止、失败和到期均释放。到期保存部分回复、取消请求并失效 generation，显示后台中断说明；不自动重发写入请求，不承诺长期后台运行。隐藏 AI 对话图标的 UserDefaults 偏好仍保留，当前入口由全局关闭控制，不删除配置或历史。

定位按钮在取得高德有效位置后，一次性设置中心、zoom15 和当前面板遮挡对应的视口锚点，不沿用点击前的缩放；首次定位等待位置回调，减少动态效果时立即更新。

底图由设置的本地 mapRenderer 偏好选择（默认系统地图/Apple MapKit，保留已保存选择），独立于 MapConfiguration 的服务端 provider 元数据。苹果使用 MKMapView，国内底图渲染边界与高德统一使用现有 GCJ 转换；标记、路线及镜头正向转换，POI、长按、地图视口与原生定位蓝点返回内部时逆向转换。国外沿用现有坐标适用范围判断。API 与存储保持 WGS-84，不要求高德隐私同意或 Key。Google 可选，Key 为空时静默返回系统地图渲染，不初始化 Google SDK。苹果首版支持地点、搜索标记、路线显示/点击、POI、长按添加、视口搜索和定位；选中日期的路线方向箭头由三个底图共用的 RouteMotionOverlay 绘制。

## Google 地图配置与共享标点

在被忽略的 `Config/Local.xcconfig` 填写 `GOOGLE_MAPS_IOS_KEY = <key>` 后重新构建即可使用 Google 底图。Google Cloud 项目需启用 Maps SDK for iOS 和计费，Key 的 iOS 应用限制绑定实际 Bundle ID（默认 me.mapannai.ios）。Key 从 Info.plist 的 GoogleMapsIOSKey 读取，初始化仅执行一次；不把 Key 放进服务器/API请求，也不接入原生 Places 或 Directions SDK。CI 的同名 Secret 可选，缺失仍可构建。GoogleMaps 由官方 SPM 包固定版本并保存 Package.resolved；校验 GoogleMaps_GoogleMapsTarget.bundle/GoogleMaps.bundle。

导航设置可选择 Google，通过官方 HTTPS Maps URLs 传入 WGS-84 目的地、api=1 和 dir_action=navigate，已安装时可由系统打开 App，否则浏览器打开，无需地图 SDK Key。

地点绘制统一在 MapMarkerAppearance：44pt画布、28pt圆圈、12pt居中emoji，选中蓝色/放大/外圈，低缩放10pt圆点；图像按图标和状态缓存。高德、MapKit、Google适配层仅负责坐标、SDK覆盖物、锚点和事件。搜索标点复用SearchPinAppearance，临时选点复用MapMarkerAppearance.draftImage。路线方向图案共用RouteArrowAppearance（1.2pt笔画、5pt长度）与90pt目标间距。高德使用MAPolylineRenderer.strokeImage的6×90pt纵向纹理，折角朝纹理上方以对应路线起点→终点（与Google纹理方向相反）；Google使用GMSTextureStyle和投影长度GMSStyleSpansOffset（6pt图案段、84pt空白段），缩放更新原生样式分段。两者纹理由同一矢量折角生成3x图像。MapKit仅使用纯原生MKPolylineRenderer绘制描边和彩线，无箭头或虚线装饰。无draw重写、镜头驱动失效或自定义线宽换算，低缩放统一隐藏。没有独立箭头覆盖物、镜头追随图层、地理折角缓存或180ms延迟重建。SDK纹理周期、转角与MapKit连续缩放视觉效果仍需真机验证，不能以模拟绘图测试代替。

定位交互共用 LocationFollowMode：idle→centered→heading→centered；第二次实心location.fill，第三次空心location并恢复北朝上，单指拖动退回idle，双指缩放/旋转保持跟踪，第二根手指抬起也不转换为拖动。MapNavigationGestures只观察SDK已有识别器，不增加竞争手势。MapKit使用原生follow/followWithHeading及原生定位动画；高德与Google使用共享CoreLocation heading驱动镜头方向，手势期间暂停镜头更新，保留用户缩放；退出Google销毁时停止方向监听。方向跟随需真机传感器验证。

本机地图凭据统一管理于被忽略的 Config/Local.xcconfig（建议权限0600），不另建含Key的env。AMAP_IOS_KEY与GOOGLE_MAPS_IOS_KEY是唯一嵌入App的字段；GOOGLE_API_KEY、AMAP_API_KEY、AMAP_JS_KEY、AMAP_JS_SECURITY_CODE可作为本地管理记录，代码不读取、不嵌入。服务器现有Key若用于iOS，须确认允许Maps SDK for iOS及实际Bundle ID；不能把服务端IP限制的Key视为已验证可用。Local.xcconfig不提交，example只保留空字段。

POI反馈共用MapInteractionFeedback（0.22秒出现/消失，尊重减少动态效果）与revealTarget视口边缘避让；临时选点置顶。MapKit/Google的路线点击经MapTapArbiter短暂等待SDK POI回调，标点/POI优先取消路线提交；已保存标点优先44pt命中。各SDK底图POI命中范围由SDK提供，真实重叠点击仍需分别真机验证。

底图POI反馈优先使用SDK能力：MapKit保留MKMapFeatureAnnotation原生选中，不叠加草稿图标；Google按官方示例使用无图标GMSMarker的默认信息窗口（SDK无默认POI点击UI）；高德保留共享自绘草稿标记。关闭/替换草稿清理原生选中，长按空白处仍用共享标记。添加页面、遮挡避让和点击优先级保持应用统一流程。

## Official POI references

Marker 顶层可选 `placeReferences` 采用服务端 apple/google/amap → `{placeId}` 合约，缺失/null 均兼容旧数据。搜索结果、草稿、创建请求和地点快照保留该字段；普通内容编辑省略引用 patch。附近反查只补名称/地址，不采用其身份；创建去重以服务端返回引用为准。高德 MATouchPoi.uid、Google 点击回调的 placeID 及 Apple MKMapItem.identifier 是唯一原生身份来源，不从内部搜索 ID、名称或坐标推断。

Apple 点击使用 MKMapItemRequest 获取正式地点，保存前等待同一草稿/坐标/连接的解析结果，服务切换或换点取消旧请求。iOS 18+ 将 identifier 持久化；导航通过 identifier 恢复原生 MKMapItem，失败使用坐标兜底。iOS 17 在当前连接会话内保留新建地点的原生 MKMapItem，重启后使用坐标兜底。原生 MKMapItem 直接交给系统地图，不再转换坐标。Google URL 有引用时增加 destination_place_id；高德保留现有坐标导航，保存 uid 不代表其导航 URL 能打开官方详情。

## Native route drag insertion

路线内排序在拖动开始时冻结列表内容坐标中的行边界，以固定行中线判定插入位置。相邻行只执行位移动画，不改变判定边界；同一目标不重复启动动画。实际让位顺序改变时用 UIImpactFeedbackGenerator(style: .medium) 提供一次清晰的换位反馈，停留及等价插入边界不重复触发。提起与放下不追加 UIImpactFeedbackGenerator，避免与系统拖动反馈叠加。松手使用与动画相同的固定几何判定，同路线移动仅在模型边界转换时补偿一次源元素移除。滚动通过列表内容坐标自然计入。系统保留拖起预览，内部排序使用 unspecified proposal，避免系统同时创建另一处让位空隙；结束、离开和取消时恢复行变换。路线内排序、未收入路线拖入及跨路线移动共用同一冻结边界、让位动画、触觉反馈和松手提交；外来地点按源行高度挪出空位，不改变行尺寸。

动画可接受状态按本地拖动 payload、固定内容坐标及列表视口判定，不跟随正在让位的行矩形切换 move/cancel。所有当天地点拖动均返回 unspecified proposal，关闭 UIKit 的第二套自动让位；固定分界线越过后立即触发共享动画，不设置 slow cadence 或悬停定时等待。路线行不自定义缩短的地点预览，采用原生完整行快照，避免拖动预览与含交通/笔记的源行高度不一致。未收入路线和路线内部排序共用同一 UICollectionView drop delegate。 路线行几何保存在非观察型引用缓存中；GeometryReader preference 更新只改变命中数据，不发布 SwiftUI 状态、不重建 List。drop adapter 每次读取最新缓存，仍能处理滚动与宽度变化。`--route-drag-diagnostics` 仅供 UI 回归测试统计拖动开始到提交前的 representable 更新次数，测试要求为 0；正常启动不显示诊断内容。

定位显示在启动时开启，前台持续更新；初次定位授权仍由系统决定。三个地图共用 UserDirectionIndicator 的传感器与蓝色渐隐方向光束（无描边，从蓝点向外径向渐隐），获得有效 heading 后即显示，朝向相对地图 bearing 转换。定位按钮循环为居中→方向居中→居中；单指拖动退出跟随但保留位置及方向标识；双指缩放和旋转不退出。状态1北向上、状态2按用户 heading 旋转，两态均将当前位置放到 MapLayout 未遮挡区域中心并使用合适缩放；MapKit使用layoutMargins计算未遮挡视口与原生跟踪动画；高德/Google使用SDK视口锚点与镜头动画。无 heading 数据时保留位置点，不伪造方向。

规划路径的展示几何统一由RouteProcessing→PlannedRoutePresentation处理，三个SDK及点击命中共用结果。每个地点区间移植Web `src/lib/map/route-geometry.ts` 的 `smoothRoutePath`：0.3m去重，端点入口绕行裁剪（弧长≤500m、范围≤180m、端点距离≤65m），地点附近或小型闭环剪枝，30m走廊内短弯简化，6m误差RDP，再去除短尖刺折返并以最大45m半径局部圆角。参数与处理顺序保持Web一致，固定样例逐坐标对照Web输出；Swift保留后台执行及取消检查。贝塞尔选项和fallback不变；原始API路径/距离仍存RouteCache，展示结果不回写。RouteOverlapPresentation在RouteProcessing内统一处理不同规划区间的反向共线：夹角点积<-0.94、横距≤5m，双方沿各自行进方向左侧偏移最多8m，距端点40m内渐变归零；16m采样和32m空间索引，超过200km单段暂不偏移。保留unseparatedPoints避免刷新累计偏移；所有SDK及命中读取同一展示points。偏移为地理米数，随地图缩小屏幕间隔会减小；同向/交叉/fallback不主动错开。

路线规划仅保留开关，移除全局自动/步行/驾车选择。`POST /api/directions` 发送起终点和当前有向相邻访问的 `transportMode`（无交通安排时省略），不发送旧 `mode`，映射及默认选择由服务端负责。开启规划后，没有可用规划路径的段（等待请求、请求失败、所有非空fallback，含NO_ROUTE/UNSUPPORTED_MODE）均绘制虚线贝塞尔；关闭规划时保留实线关联曲线，保留服务端distance用于列表展示（fallback为服务端计算的两点距离），距离不参与实虚线判断。缓存v2隔离服务器/provider/交通方式/有向端点；公交、地铁、火车成功和NO_ROUTE缓存1小时，其他终态fallback保留。交通方式修改或拖动改变相邻边后重新匹配；过期缓存不得被保留的显示几何跳过。正常路径仍使用共享Web展示剪枝及iOS往返分离，不改变服务端路径与距离。

虚线和实线共用高德基准线宽：普通色线3.5pt、选中色线6pt，描边总宽分别5.5pt和8pt，三个地图一致；虚线短段同时绘制描边与色线。MapKit不使用lineDashPattern，而由RouteDashGeometry按8pt短段/6pt间隔切割曲线，用普通MKPolylineRenderer实线绘制；缩放每1/8级更新切段，平移在预留一屏范围内复用，超出后仅补绘可见范围，原路线保留用于命中。高德/Google沿用SDK虚线。

高德自由操作时缩放围绕双指中心；手势及惯性移动期间不切换缩放锚点策略、不重设中心坐标，方向更新暂停镜头跟随。移除regionDidChange中的锚点重设，避免旋转结束叠加第二次平移。定位按钮仍使用可见区域锚点。

地图zoom<10时，三种底图统一使用路线相邻地点的起终点贝塞尔曲线连接，线宽固定1pt，统一深莓红、不按日期区分，无描边/箭头/虚线/选中加粗，置于marker下层并禁用路线命中；不使用规划几何，放大恢复已有路线缓存。

高德关闭俯仰倾斜手势（isRotateCameraEnabled=false），初始cameraDegree=0；保留水平旋转和双指缩放，避免双指操作进入倾斜视角。

## 旅行档案卡堆

“我的旅途”是整页卡堆首页。Top优先展示所有开始日期≤今天≤结束日期的进行中旅途，按出发日期倒序、同日按ID稳定排序；每张完整204pt高，彼此及后续卡堆之间保留24pt间距，右上角显示6pt素绿色圆点和caption“旅途中”。没有进行中旅途时选最近的未来出发；两者都没有时按出发日期到今天的绝对距离选择Top。所有Top不在其余列表重复出现，其余未结束旅途及已完成旅途各自按开始日期倒序，同日按ID稳定排序。首页标题“我的旅途”在ScrollView内使用largeTitle，不作为navigationTitle。排除Top后，所有剩余旅途按出发年份分组，每个年份前插入204pt不可点击年份卡，共用82pt堆叠步距，不另加区块间距；没有未来旅途也显示年份分组。年份与右侧小字次数在露出区域中排列，不带图标或完成标签。年份乘固定整数种子生成低饱和配色和圆环／曲线／折线图案，坐标、颜色与模式只取决于年份，不使用随机数、hashValue、网络或持久化，刷新和重启一致。单击卡片进入整页旅行详情，卡片从原位置移到顶部；顶部卡片下方显示天列表，原生push展示每天安排。×返回首页，地图按钮进入现有地图工作区，返回保留整页上下文。未选中的完整Top卡在原位置淡入淡出，不随压叠卡上下移出/恢复，前置压叠卡及所有年份卡的移动裁切在Top下方，避免穿过完整Top表面；所有年份卡使用同次UIKit快照转场及原始层级（按插入位置保存各自frame），避免返回途中露出或交接闪现。详情实卡与UIKit快照同步切换可见性，实卡关闭额外opacity动画，避免继承日程List淡出而与移动快照重影；日程正文保留淡出。选中卡轨迹、时长与压叠卡移动保持原样。首页ScrollView不重排、不补偿contentOffset；设置位于旅途计数下，未加入行程的地点保留首页。

转场层按原索引真实遮挡，所有卡片保持完整204pt高度。选中卡片始终清晰；转场开始前用ImageRenderer生成可见卡片快照，邻卡的模糊图也只生成一次。UIViewPropertyAnimator以0.48秒、dampingRatio=1的弹簧动画驱动快照位置、尺寸和透明度，运动期间不重新布局文字、不动态模糊List；上下邻卡分别作为一组移动到可见区域外。详情列表保持目标布局，延迟0.12秒淡入。落位后交给List真实头卡，转场层不参与命中或无障碍。头卡与天列表共用滚动，不固定。旅途详情顶部关闭按钮保持原导航位置，以44pt独立圆形regularMaterial背景保证辨识；iOS26隐藏列表顶部scroll edge effect，不用整条导航渐隐覆盖正文，保留导航安全区与转场几何。List头卡通过global坐标测量，再扣除首页内容容器的global原点，避免原生List丢失命名坐标空间后重复计入导航安全区。关闭先捕获头卡当前滚动矩形，再由同一UIKit转场层反向归位；首页保持原滚动位置。减少动态效果只淡入淡出。滚动几何写入非观察缓存，旅行选择和路线刷新在落位后执行。Info.plist启用CADisableMinimumFrameDurationOnPhone，允许支持ProMotion的手机使用高刷新率；实际帧率仍需设备录屏或Instruments验证。

旅行内的天列表按独立原生分组显示：第N天与本地化日期、已有当天主题、最多两行地点摘要、地点/路线数量。空日显示未安排状态，保留长按/左滑删除和跨日拖放。地点详情使用共享贴边白底面板，默认半屏。

旅途转场在点击后即准备 UIKit 快照，同时构建详情布局；位置连续两次16ms采样稳定后直接启动，无额外16ms交接等待。复用 Core Image context，保留0.48秒弹簧、终点坐标与关闭轨迹。

只读多旅途置顶预览：`--demo --archive-preview --ongoing-archive-preview`。

已改版旅途页面的操作按钮共用 `JourneyActionStyle`：白底深色图文胶囊、轻描边与阴影、至少48pt高度。首页设置居中位于旅途次数下方；每日列表的添加地点/添加一天/编辑旅行同排，采用紧凑图文间距；天详情的添加地点/新建路线并排，操作组左边缘与上方内容卡片对齐，辅助功能大字模式改为纵排。仅调整入口样式与排列，表单内部、业务动作及首页卡片转场保持原实现。

## 新的旅途

新建旅途从首页及地图入口使用独立fullScreenCover，标题“新的旅途”。整页采用简洁名词标题、紧凑白色输入区和底部纯文字黑色“创建旅途”按钮；iPad内容最大560pt居中。首项“目的地”搜索省市，按选择顺序显示编号列表及移除按钮，至少一处、最多20处；名称/图标同排，图标使用不透明系统白底（深色模式跟随系统）的5列可滚动弹出面板，完整复用Web的60个预定义旅行图标，选择后收起；键盘不主动唤起，输入时收紧布局，safeAreaInset保留键盘上方操作区。

日期范围在同页展开自定义月历，先点出发、再点结束，黑色端点与浅灰连续范围（灰带与圆同高，起点仅右半边、终点仅左半边，延伸至圆心并由圆盖住；同日不画连线）；反向点选归一化，同日为1天，切月保留范围，完成仅收起日历。TripDateRange按本地Calendar计算包含两端的日数，最多367天；保存及草稿恢复显式转换既有UTC日期编码，避免时区和夏令时偏移。编辑旅途复用同一页面与图标、名称、范围月历，整页呈现。范围允许整体改期和延长，至少保留原行程天数；少于原天数禁用保存。原日期ID、地点、路线与时间按顺序保留，新日期为空白。保存前读服务器快照，先PUT顺移原日，再读取新日期列表，仅POST缺失日期，最后PUT结束日期；部分失败回滚本地并保留草稿，重试读取已创建日期以免重复追加。编辑不发送目的地字段，保留服务器元数据。

同步校验和写入预留后立即关闭；后台保存、重复提交保护和失败“继续编辑”沿用AppStore。创建草稿以整页恢复，编辑草稿保持sheet。测试使用只读示例和URLProtocol mock，不向生产服务写入。

旅途/天详情底部胶囊操作使用紧凑行内边距，不添加透明Section页头占位。未安排日期地点复用天详情的emoji、名称和地址样式，未安排日期与天详情未收入路线共用卡片内标题，右侧数量采用深色数字与次要色单位；空列表隐藏整个分组与标题，添加地点胶囊仍保留，保留原点击、滑动移除和跨日拖放。

搜索结果采用白色分组、加粗名称与次要色地址、无行分隔线，中性圆形添加按钮；搜索框使用中性圆角输入区。保留现有范围搜索、分页、已保存标识、选点与添加草稿流程。

Trip已持久化有序目的地名称与WGS-84中心，创建支持多个目的地。地图尚未使用目的地定位空旅行，空旅行仍保留现有视野；已有地点适配实际地点。目的地合约没有行政区边界字段，不从旅行名称猜城市。

搜索结果正文切换到地图并打开贴左右及底边的半屏地点详情，仅顶部圆角；拖动顶部手柄只在半屏与全屏之间切换，半屏禁止继续下拉压缩，关闭按钮返回搜索，地图背景可交互，顶部大标题与分类、地址/电话、有效评分及已保存标识，仅展示搜索接口实际字段，不将用户笔记或用户封面混作POI信息；底部加入旅行/当天或收藏及导航，未接入的照片、介绍和营业时间不生成占位内容。添加草稿在详情之后导航进入，取消保留半屏详情，返回搜索恢复原弹窗、关键词和分页结果。搜索详情导航当前打开Apple Maps。

目的地搜索调用已存在的 `GET /api/destinations?q=…`（响应 `{data:[{name,latitude,longitude}]}`），不继承地图范围或国家限制、不调用原生POI搜索。输入400ms节流，换词/退出/切换服务取消旧任务，取消结果不发布；提供空结果、错误及重试。创建POST附带有序destinations数组，WGS-84坐标经过有限值与范围校验，坐标按六位小数去重，失败草稿保留全部目的地及顺序，重试复用已创建ID；编辑旧旅行不改目的地，读取兼容旧destination单值与新destinations数组，新数组（含空数组）优先。只读示例使用本地目的地结果，不向配置服务发送请求。

## 地点与路线编辑页

添加/编辑地点共用systemBackground白色连续滚动页、22pt分组标题与细分隔线，移除嵌套白卡，名称与分类同排。分类保留5列图标白底面板；位置仅展示已有地址，坐标由地图选点维护。封面保留全宽16:9与8pt圆角，笔记入口为全宽无卡底行，进入既有独立编辑器；底部黑色胶囊添加/保存，上传时禁用，保留搜索目标、部分创建重试与失败恢复。嵌入搜索的返回仍确认有修改草稿。

新建/编辑路线使用白底plain List、同样标题与白底固定胶囊按钮，保留系统分隔线，访问顺序带01起始序号、地点名及地址；使用原生拖动手柄与删除控件，不改变每日成员。独立弹窗使用关闭图标，嵌入搜索导航保留返回图标。当天地点搜索位于添加分组内，右侧中性圆形加号加入草稿；新路线至少一个地点，保存同步提交本地更新、后台写入，拒绝覆盖外部路线变更。

日期移动/复制选择器使用白底连续选项行及细分隔线，不再为每个日期套圆角卡片。地图内日期标题长按入口复用JourneyDayEditor，移除旧日期标题alert及无入口的重复代码；地图工作区统一持有该sheet，避免旅途列表和地图同时呈现。系统权限、错误、放弃修改以及简单删除/移除alert保留原生交互。

只读编辑页截图可用 `--demo --archive-preview --editor-preview trip|place-new|place-add|place-edit|route-create|route-edit`；无真实接口写入。

## 日详情地图浏览

最小日详情使用 `DayMapPresentation.contentHeight`（140pt，外层另计设备底部安全区修正）统一布局与地图遮挡；地点卡66pt高、浅灰底和细边框，不加载照片，分类SVG位于左侧。名称、地址、时间及交通信息均单行尾部省略，连接箭头上下显示方式/车次与时间。普通卡右侧露出下一站并渐隐；末站可用整行宽度，滚动到末站后取消渐隐。半屏与全屏复用同一日详情，保留地图上方间隙与原生拖动区。 顺序遵循当天各条路线，未安排成员在末尾；不同路线或未安排点之间不伪造连接。无交通时间时可显示原距离摘要；距离优先取同段已规划、非fallback的有效距离，缺失时按原行为明确标注“直线”，不冒充实际里程。

进入一次适配当天地点和已显示路线，面板遮挡参与镜头计算。`dayMapBrowsing` 隔离当前日地点／路线，焦点独立于地点详情选择；地图适配器共用编号图像，焦点黑色，普通编号蓝色，点击标记同步行程链并打开地点详情，点击卡片也可打开详情。横向滚动换焦点可提交SDK原生镜头命令，纯刷新或几何补全不定位。手动拖动／缩放通过既有 `noteMapInteraction` 停用镜头跟随；后续滚动仅切换焦点。定位按钮复用当前位置逻辑，切换日期重新初始化。行程卡与半屏／全屏日详情共用一个贴边面板及拖动手柄，上拉展示共享 `DayDetailPage`，下拉恢复行程卡；全屏仍保留顶部安全区与64pt地图操作区，不替换地图实例。地图不跟随磁盘或API返回反复移动。


### Day detail reuse contract

- Date cards in `JourneyDaysContents` call the archive day-selection callback directly. `HomeView` opens the day map with the draggable panel at full height; no archive day NavigationStack destination or trip-wide map entry remains. Returning closes the map workspace to the existing trip card list.
- `DayDetailPage` from `TripsView.swift` is the expanded half/full page, retaining `DayContentsView` route editing/transfer/deletion. Expanded presentation includes `DayMapDateStrip` and the optional day theme with place/route counts; compact presentation shows the same date strip plus `DayMapJourneyView` cards. No repeated day navigation title or panel toolbar controls. Entering from a trip presents the day panel at full height without a second slide-in after the map. Compact cards use category artwork instead of photos, with single-line tail truncation for every text field. The final card fills the available width and has no trailing fade. Expanded place names allow two lines, addresses stay on one line and offer copying the full address. Place/trip icons reuse the 13 SVG assets from Web commit ca8c400 in the asset catalog; emoji persistence and API values remain unchanged, and unmapped emoji retain their existing presentation. Map-level uncontained controls: top-left returns to its trip detail, preserving the archive state and scroll position; top-right opens the shared trip name/date editor. Place long press retains inline day editing and produces a light haptic. Expanded place rows align artwork, name/address and visit time at the top. Selection mode shows only artwork/name with native selection/reorder controls, hiding ordinals, addresses, notes, transport and create actions. Its bottom actions have 44pt height with a compact selection summary. The first cover frame includes the full day content while UIKit prepares the draggable presentation. Full day panels reserve 64pt below the top safe area so both controls stay visible and hittable.
- Keep compact and expanded content mounted inside one panel. UIKit follows the finger and settles with an interruptible damped spring; content opacity follows measured panel height, with a spring on snapping. Reduced motion uses immediate settling. Preserve the selected stop and list state during height changes.
- Day-map date strips use 44pt intrinsic height. Top inset is 14pt; the visual inset is independent of the 96pt vertical gesture area. Other panels retain 24pt top inset. A downward vertical list gesture at its top hands off to the panel; horizontal date/card gestures remain independent.
- Map tool controls use measured panel height and a 16pt gap; do not infer half height from a smaller safe-area GeometryReader, which places controls against the panel.
- Background stays `systemBackground` at all day-map heights. Daily place identity and horizontal cards use `DayPlaceArtwork`, preferring `Marker.content.headerImage` through `imageURL` / `JourneyPhotoCache`. Category artwork is a fallback only.
- Display counts and unplanned groups use existing marker IDs, consistent with Web. The server may retain a deleted ID in `markerIds` while marker detail returns 404. Preserve those raw memberships for round-tripping; do not display/count a phantom fourth place or an empty group, and do not repair production data automatically. Only explicit user writes change memberships.
- Camera focus remains independent of height changes; manual pan/zoom keeps camera following disabled. Connector redesign remains a proposal until selected. Do not alter travel-card transition timing for daily map work.

搜索地图保留全部已保存地点及底图 POI，不沿用当天成员过滤。首次搜索加载状态在结果区居中；分页加载保留现有列表和镜头。地点详情跳过 point_of_interest / establishment 等通用分类，具体分类显示中文名称，已保存地点优先显示自身类别。

已保存地图标点点击打开地点详情；当天行程链横向滚动仅更新焦点。手机详情使用同一贴边面板默认半屏，可上拉全屏，下拉至80pt关闭并恢复原旅途档位与导航。头部左侧使用无背景48pt分类SVG（随动态字体缩放），右侧名称与地址紧密上下排列，图标对应一行名称与一行地址的信息块高度，不再单列类别文字。封面与所属行程／笔记随后，操作区随内容滚动，未加入目标日时明确显示目标日期。无封面、笔记或归属时不创建空内容区。

旅途图标显示复用 Web 9262859 的55个 SVG（含手绘国旗），与地点图标共用资产映射组件；未知值保留 emoji 回退，存储及API仍使用原 emoji。

天详情中的路线地点行与未安排地点行共用地点选择入口，打开半屏地点详情；关闭动画恢复进入前的天详情档位。仅焦点浏览调用focusDayMapMarker，不用于列表地点点击。地点编辑只展示已有地址，位置由地图选点维护，不显示或输入经纬度，保存沿用草稿坐标。

手机定位/搜索浮动控件在面板拖动及呈现、关闭、档位切换期间隐藏，使用UIKit真实动画完成回调在落定后从右侧滑入，不逐帧跟随面板。减少动态效果时直接显示。面板头部两侧按钮保留触摸，不由中心拖动区域抢占；地点详情关闭按钮使用完整44pt矩形命中区。

日详情原页编辑的完成入口为右上角44pt对号，底部仅保留选择与移动/复制/删除操作；进入和退出沿用同一列表动画，修改仍即时保存。手机镜头遮挡使用实际面板高度，最高按半屏计算；最小及半屏以未遮挡区域中心定位，全屏复用半屏参数，日地图镜头命令不强制使用最小档高度。

地点编辑的空封面入口保留16:9全宽比例，采用柔和中性底色、28pt轻线重相片加号图标、subheadline标题和caption说明，居中布局；选图后仍使用原有16:9图片裁切、上传及替换流程。

首页旅途卡片ScrollView使用refreshable下拉刷新，复用AppStore.refresh(force: true)的请求合并、连接/数据版本隔离及错误保留旧数据机制，不重置卡片展开状态或导航。

地点详情导航/编辑/删除复用JourneyActionGroup(compact: true)，与日详情添加地点/新建路线采用同一字体、图标尺寸及胶囊样式，删除显示红色图文；可选加入今日单独排列避免四按钮挤压。

地点详情在所属行程信息行下方、笔记上方依次显示导航、编辑和“从今日移除”，删除独立靠右，操作与正文一同滚动，不固定底部；今日移除仅在所选日期包含该地点时显示，确认后复用 `removeDayPlacesInBackground` 清理当天成员与全部路线引用，保留收藏与其他日期，失败沿用后台保存回滚。所属行程入口使用白底无容器信息行，移除重复地图图标，保留名称、第N天及箭头，以细线与地点信息分隔。移除底部操作区渐隐背景；详情ScrollView延伸至顶部面板边界，内容只由面板外轮廓裁切，不在拖动条后方叠不透明安全区横带；非成员继续显示加入今日。

添加地点工作区点选已保存标记时直接嵌入共享 `MarkerDetailView`，不创建第二套详情：标题、主题分类标签、保存地址、封面、所属日期、笔记、导航／编辑／当前目标日移除／删除及随正文滚动的操作区均共用。搜索嵌入版本不读取其他 `selectedMarker`，当前日依据冻结的添加目标，不改变搜索档位恢复；编辑在原 NavigationStack 内 push，关闭／取消保留搜索。非目标日成员只在显式加入后修改成员，不因预览添加。未保存POI保留服务端可用信息和明确添加入口，标签／地址／关闭与底部渐隐沿用详情视觉。

搜索半屏／全屏使用systemBackground白底，最小80pt内容档使用白色背景和56pt搜索行，保留顶部拖动条，底部另计安全区；输入框可点击恢复半屏，返回退出搜索。收起／展开沿用共享面板弹簧高度动画及0.22秒背景过渡，减少动态效果时直接切换。展开结果使用plain List、轻分隔线、24pt左侧对齐，地点名称中等字重与最多两行地址，已保存地点保留分类SVG；标题右侧仅显示结果数量，移除添加目标教学文案。保留分页、加载居中、错误重试、明确添加和档位恢复。

最小档搜索使用白色贴边面板与原生56pt搜索行，不叠加胶囊背景或阴影；移除旧固定48pt胶囊裁切遮罩，保留可点击/拖动的顶部指示条。地图遮挡仍使用80pt内容高度，安全区只在面板外框计入一次。

日期菜单使用“编辑／删除”短标签，编辑页标题为“编辑”。仅更改主题发送title，不重写markerIds/chains；已有但尚未加载的地点引用保留，只校验新选成员。全局操作错误和当天编辑校验错误使用白底自适应确认面板，保留知道了/继续编辑；恢复编辑由错误面板onDismiss交接，避免同时呈现两个sheet。

空旅途名称使用本地30个地名与20个双字主题的随机滚轮提示，不写入草稿；两列每轮独立随机移动4或5格，地名向下、主题向上，共用1.4秒加减速进度，落定后停留3秒。聚焦、输入、离页或后台停止；减少动态效果及VoiceOver使用静态组合，宽度不足时回退普通提示。名称提示与目的地搜索共用19pt medium字体；三个词组在同一Canvas按实际文字宽度连续排版，不插入空格。

旅行创建/编辑页统一白底连续章节，名称和日期取消旧圆角卡底与双层水平内边距，保留图标选择、日期范围日历与固定提交按钮；设置同样移除嵌套卡片，分组和所有配置行为不变。

地点详情保留24pt外边距，头部无背景48pt分类SVG与title3名称／地址组合，模块间距14pt，封面8pt圆角；笔记用分隔线及章节标题组织。详细日行程与最小横向链路按“日详情地图浏览”一节实现。笔记编辑保留原生富文本、图片上传/删除、格式工具和放弃修改确认。

地点详情在所属行程行显示第N天与完整日期，勾选仅标记当前选中的目标日，不再重复显示“在今日行程中”；未加入时按钮明确显示目标日序与日期，无目标日不显示加入操作。

手机地图内搜索、日行程与地点详情共用一个EdgeAttachedPanel，后台保留日行程实例和滚动位置；切换只交接内容和detent，不串行dismiss/present。内容同时交叉淡化0.14秒，地点间切换不再整页横移；高度吸附0.28秒、无回弹，移除高度回调额外0.42秒动画与内容独立档位动画。关闭地点恢复进入前档位，打开所属日期恢复半屏，地点编辑仍使用独立表单。搜索保持独立NavigationStack，后台行程仅隐藏并停用交互，退出恢复原页面与档位；搜索切换使用同一0.14秒交叉淡化，不再串行关闭旅途再弹搜索。搜索草稿仍在搜索栈内push/pop。iPad和非日地图地点入口暂保留独立面板；减少动态效果禁用附加动画。

搜索最小档的NavigationStack忽略底部容器安全区，由外层统一预留底部安全区，避免56pt搜索行与24pt拖动区被二次挤压；搜索详情及添加草稿不提供最小档，拖动最低保持半屏。

首页操作采用标题右侧44pt齿轮设置与右下角52pt圆形新建按钮，移除列表底部设置操作和旧导航栏加号；打开旅行后隐藏悬浮新建，列表底部留84pt防遮挡。顶部置顶完整卡保持正面；下方收纳卡与原有特殊年份卡使用随滚动位置变化的X轴透视；年份卡采用固定年份色相的实色彩纸底，浅深色分别控制饱和度与亮度以区别页面中性背景，基础露出高度88pt，上半屏按线性间距梯度进一步收紧（位移为梯度积分，最多向上48pt），下半屏保持基础间距；置顶完整卡与收纳组之间额外预留最大收紧位移，确保上提后仍保留至少24pt分组间隔，转场裁切边界不向上侵入置顶卡；静态展示与转场共用收紧位移，减少动态效果关闭位置收紧：以视口中线与首张收纳底牌中心两者较低位置为放平边界（首张年份底牌始终放平，后续卡片从此线性分配倾角），卡片中心在上半屏时为0度，下半屏按归一化距离线性渐变到-60度，在视口底部上方84pt（底部控件预留区）达到最大值；向上滚动时倾角线性减小，到中线时完全放平，超出边界钳制；移除临时倒向与曲线开关；visualEffect直接读取几何，不逐帧更新页面State、不吸附滚动，辅助功能大字取消透视并完整展开。SwiftUI静态展示与UIKit转场使用同一中心变换矩阵和原始布局框，转场每张卡使用普通CALayer容器先合成内部透视，再按原列表顺序固定叠放，年份卡同规则；下方永远覆盖上方，不改变选中卡层级。抽出期间保留不可见原槽位，冻结打开时视口高度和选中卡原始bounds/position/transform；下方卡继续按完整队列布局，返回直接恢复冻结姿态，不从飞行中的卡片重新求倾角。0.30秒统一时间轴，选中卡位置、尺寸与倾角同步飞向详情；使用近似ln(x)的cubic曲线（起步快、接近目标慢），展开与收起同曲线反向运行；28%进度后上方组向上、下方组向下退场，不透明遮挡不提前淡出。返回时两组与选中卡同时回场，选中卡连续飞回，逐渐插入下方卡之后。移除抬起44pt与多阶段扶正逻辑；中断接续呈现层状态，旅行与年份卡统一先在204pt画面内部应用透视与收紧，再在外层测量未变换槽位；避免把已偏移的frame再次收紧。关闭直接无动画交接，不使用80ms延时补丁；首页标题留在原层随上方组向上退场、向下回场（减少动态效果才淡入淡出），转场快照包含视口外204pt的卡片余量并复用外层裁切，避免底部露出的年份卡在开始/结束时突变；详情容器在飞行完成时才接管显示，不做整体透明度动画，防止头卡交接继承半透明而改变封面白色遮罩；点击不生成高斯模糊位图；旅途封面在首页待机时持续预缓存旅途封面与每日行程封面，详情头图优先读当前缓存，避免重复打开时白色占位后再补图。减少动态效果只交叉淡化，不执行3D运动。

旅行详情关闭按钮保留稳定ToolbarItem占位，仅在详情未关闭时显示并可交互；返回开始即隐藏并移除无障碍入口，卡片归位完成时不增删工具栏项，避免首页短暂残留×及导航栏布局跳动。
