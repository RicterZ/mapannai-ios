# MapAnNai iOS（マップ案内）

[English](README.md) | 中文 · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [下载 IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

把想去的地方放到地图上，再把每天的旅行计划带在身边。

MapAnNai iOS 是 MapAnNai Plus 的原生 iPhone 和 iPad 客户端。你可以收藏餐厅、酒店和景点，记录照片与笔记，按旅行和日期安排访问顺序。客户端与网页使用同一服务端的地点和旅行数据，在电脑上做好的计划，可以在手机上继续查看和编辑。

## 产品功能

- **收藏地点与旅行笔记**：搜索想去的地方，点击地图上的兴趣点或长按地图添加地点，记下攻略、预订信息与旅行见闻。
- **按天安排行程**：创建旅行，先把地点收藏到“未安排日期”，再长按拖入某一天；当天独立地点可拖到路线标题并追加到末尾。把地点加入每天的安排；支持增减日期、调整出发时间，复用已经收藏的地点。删除旅行或某一天时，可选择同时清理独占地点，共享地点保留。
- **自由组织访问顺序**：一天可以有多条路线，调整地点顺序，分别安排不同活动。
- **在地图上看清整体安排**：查看全部地点、某次旅行或当天路线，用颜色区分日期，点击地点或连线查看对应行程。
- **查看路线与打开导航**：支持步行、驾车和自动路线规划，出发时可以从地点打开系统地图或高德地图导航，在设置的“打开地图”中选择。
- **在手机和平板上使用**：iPhone 上收起胶囊可切换旅行日期，iOS 26 及以上采用液体玻璃，较早系统使用毛玻璃，拉起查看行程，iPad 上地图与行程并排显示，方便比较地点、整理安排。
- **与网页共用旅行数据**：连接自己的 MapAnNai Plus 服务，在 Web、iPhone 和 iPad 上继续编辑同一份旅行。

## 开始规划

1. 在应用设置中连接自己的 MapAnNai Plus 服务。
2. 搜索、点击地图上的兴趣点或长按地图添加想去的地方，记录笔记与照片。
3. 在“我的旅途”点击“添加旅途”或收起面板左侧的＋，把地点加入每天的安排，再调整路线中的访问顺序。
4. 出行时打开当天行程，查看地点、阅读攻略或打开导航。

还没有服务端？按照 [MapAnNai Plus 的部署说明](https://github.com/RicterZ/mapannai-plus/blob/main/README.zh.md#部署自己的服务) 准备服务，再在客户端填写服务地址及服务需要的 API token。搜索、保存和路线规划需要网络连接。

点击地图右上角的对话图标可使用 AI 助手规划行程，先在设置中配置模型 API。

点击每日行程中的路线标题可在地图查看整条路线，右侧箭头独立展开或收起地点列表。
开启路线规划后，相邻地点之间会显示该段已规划路径的距离。


启动时允许定位，地图会移到离当前位置最近的已保存地点；定位不可用时保留按日期选择的启动视图。

## 安装到 iPhone / iPad

需要 **iOS / iPadOS 17 或更新版本**。Release 提供未签名的 `.ipa`，可通过 **AltStore Classic** 签名安装。

1. 按照 [AltStore 官方指南](https://faq.altstore.io/altstore-classic/how-to-install-altstore) 在电脑安装 AltServer，再为 iPhone 或 iPad 安装 AltStore Classic。根据系统提示开启开发者模式。
2. 在设备上打开 [Releases](https://github.com/RicterZ/mapannai-ios/releases/latest)，下载 `MapAnNai-0.0.1-unsigned.ipa`，存到“文件”。
3. 打开 AltStore Classic → **My Apps** → 左上角 **＋**，选择下载的 IPA，按提示完成签名和安装。按 AltStore 要求保持与 AltServer 的连接。
4. 使用免费 Apple 账号安装的应用通常需要每 **7 天续签**，在 AltStore 中刷新应用即可。连接和自动刷新方式见 [AltStore 使用指南](https://faq.altstore.io/altstore-classic/your-altstore)。

这里使用的是 **AltStore Classic**，不是 AltStore PAL。重签可能改变应用 Bundle ID，而高德地图 Key 绑定 Bundle ID；如果安装后地图鉴权失败，需要使用与签名后 Bundle ID 匹配的 Key 重新构建，详见 [构建指南](docs/development.md)。不能保证任意账号重签后地图均可用。

## 自行构建

见 [构建指南](docs/development.md)。推送 main 或手动运行 GitHub Actions 会构建 unsigned IPA；推送版本标签后，构建成功的安装包会自动发布到 Releases。

## 许可

[MIT](LICENSE)。高德地图 SDK 遵循其自身授权条款。
