import SwiftUI

// Static layout shared by WidgetKit and the in-app simulator review canvas.
struct TodayWidgetCard: View {
    var large: Bool
    var rainy = false
    private let stops: [(String, String, String, String)] = [
        ("09:00", "building.columns.fill", "清水寺", "京都市东山区 · 松原通"),
        ("11:00", "cup.and.saucer.fill", "二年坂与三年坂", "石阶小巷，留一段散步时间"),
        ("14:30", "tree.fill", "八坂神社", "祇园町北侧 · 东山街区")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: large ? 16 : 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("02").font(.system(size: large ? 36 : 30, weight: .semibold, design: .rounded))
                        Text("10月16日 · 周五").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("京都的四天慢旅行").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rainy ? "小雨" : "晴").font(.caption.weight(.medium))
                    Text(rainy ? "16°—21°" : "17°—24°").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 43)
            }
            Text("古寺钟声与巷陌闲步").font(.system(size: large ? 22 : 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            if large {
                HStack(spacing: 8) {
                    Text("路线 1").font(.caption.weight(.medium))
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                    Text("3 个地点").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stops.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Text(stops[i].0).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .leading).padding(.top, 3)
                            Image(systemName: stops[i].1).font(.system(size: 17)).foregroundStyle(Color(red: 0.4, green: 0.46, blue: 0.4)).frame(width: 28, height: 28)
                                .background(.white.opacity(0.85), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stops[i].2).font(.system(size: 16, weight: .medium))
                                Text(stops[i].3).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        if i < stops.count - 1 {
                            HStack(spacing: 7) {
                                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 23)
                                Image(systemName: "figure.walk").font(.system(size: 10))
                                Text(i == 0 ? "步行 · 800 m" : "步行 · 1.2 km").font(.system(size: 10))
                            }.foregroundStyle(.secondary).padding(.leading, 61)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Text("今日 3 个地点 · 1 条路线").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption)
                }
            } else {
                Text("清水寺  →  二年坂  →  八坂神社")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("3 个地点")
                    Text("·")
                    Text("1 条路线")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(large ? 20 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { JourneyWeatherBackground(style: rainy ? .rainy : .sunny) }
    }
}

#if DEBUG
struct WidgetStyleReview: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("今日行程").font(.largeTitle.bold()); Spacer(); Image(systemName: "square.grid.2x2").foregroundStyle(.secondary) }
                    Text("小组件样式预览 · 示例行程与天气").font(.footnote).foregroundStyle(.secondary)
                    TodayWidgetCard(large: false).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
                    TodayWidgetCard(large: true).frame(height: 376).clipShape(RoundedRectangle(cornerRadius: 26))
                    Text("中号 · 日卡片    /    大号 · 日行程")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 30)
                    .frame(maxWidth: 440).frame(maxWidth: .infinity)
            }.background(Color(red: 0.92, green: 0.935, blue: 0.92).gradient)
        }.preferredColorScheme(.light)
    }
}
#endif
