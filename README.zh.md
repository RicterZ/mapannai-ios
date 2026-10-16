# MapAnNai iOS（マップ案内）

[English](README.md) | 中文 · [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) · [下载 IPA](https://github.com/RicterZ/mapannai-ios/releases/latest)

把想去的地方放到地图上，把每天的旅行计划装进口袋。

MapAnNai iOS 是 [MapAnNai Plus](https://github.com/RicterZ/mapannai-plus) 的原生 iPhone / iPad 客户端，连接你自己的服务。在网页上做好的计划，打开手机就能看；路上做的修改，各端同步。

## 能做什么

- **收藏地点**：搜索、点选地图兴趣点或长按地图，收藏餐厅、酒店和景点，配上封面照片，记下预订信息和攻略。
- **按天安排行程**：创建旅途，选好目的地和日期，把地点加入每一天；可分成多条路线、调整访问顺序，记录游览时间、交通方式、车次和出发时间。
- **在地图上看行程**：每天一种颜色，路线按访问顺序串起地点，并显示站点之间的规划距离；点击地点或路线即可打开详情。
- **回看旅途**：“我的旅途”优先展示进行中和即将出发的旅途，过去的旅途按年份叠成卡片。每一天像一个篇章，展示照片、路线和当天天气。
- **和 AI 一起规划**：在对话里描述下一次旅行，助手会追问细节、推荐日期，并起草行程供你确认。AI 在你的服务器上运行，使用你自己配置的模型。
- **分享旅途**：把整趟旅途导出为带路线和照片的长图，可直接发送或存入相册。
- **一键导航**：出发时，从任意地点打开系统地图、高德地图或 Google 地图。

支持 iPhone 和 iPad，iPad 上地图与行程并排显示。底图可选系统地图、高德或 Google 地图。

## 快速上手

1. 按照 [MapAnNai Plus 部署说明](https://github.com/RicterZ/mapannai-plus/blob/main/README.zh.md#部署自己的服务) 准备服务。
2. 在应用的设置中填写服务地址；如果服务需要，再填写 API token。
3. 在“我的旅途”点 ＋ 创建旅途，选择目的地、名称、图标和日期。
4. 搜索或长按地图收藏地点，再把它们加入每一天。
5. 出行时打开当天行程，查看地点、翻看笔记或开始导航。

搜索、保存和路线规划需要网络连接。

## 安装

需要 **iOS / iPadOS 17 或更新版本**。每个 Release 都附带未签名的 `.ipa`，可通过 **AltStore Classic** 签名安装。

1. 按照 [AltStore 官方指南](https://faq.altstore.io/altstore-classic/how-to-install-altstore) 在电脑安装 AltServer，在设备安装 AltStore Classic；如有提示，请开启开发者模式。
2. 在设备上从 [Releases](https://github.com/RicterZ/mapannai-ios/releases/latest) 下载最新 IPA，存到“文件”。
3. 打开 AltStore Classic → **My Apps** → **＋**，选择 IPA，按提示完成安装。
4. 使用免费 Apple 账号安装的应用通常每 **7 天**需要在 AltStore 中刷新一次。

请使用 AltStore Classic，不要用 AltStore PAL。重签可能改变 Bundle ID，而高德 Key 与 Bundle ID 绑定；如果高德底图无法加载，可在设置中切换到系统地图。

## 许可

[MIT](LICENSE)。地图 SDK 遵循其各自的授权条款。
