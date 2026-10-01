import SwiftUI

/// Shares the map's bounds so the native and preview tap positions need no safe-area conversion.
struct RouteDayPicker: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GeometryReader { proxy in
            if !store.routeCandidates.isEmpty {
                let width = min(220.0, proxy.size.width - 24)
                let height = min(CGFloat(store.routeCandidates.count) * 47 - 1, 276)
                let point = store.routeCandidatePoint
                let x = min(max(12, point.x - width / 2), proxy.size.width - width - 12)
                let above = point.y - height - 12 >= proxy.safeAreaInsets.top + 8
                let y = above ? point.y - height - 12 : min(point.y + 12, proxy.size.height - height - 12)
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { store.routeCandidates = [] }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.routeCandidates) { route in
                                Button { store.selectRoute(route) } label: {
                                    HStack(spacing: 10) {
                                        Circle().fill(Theme.color(route.colorIndex)).frame(width: 8, height: 8)
                                        Text(store.routeDayLabel(route)).font(.body)
                                        Spacer(minLength: 0)
                                        if store.dayID == route.dayID { Image(systemName: "checkmark").font(.body) }
                                    }
                                    .foregroundStyle(.primary).padding(.horizontal, 16).frame(height: 46)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).accessibilityIdentifier("route-day-choice-\(route.dayID)")
                                if route.id != store.routeCandidates.last?.id { Divider().padding(.leading, 34) }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: width, height: height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
                    .offset(x: x, y: y)
                    .accessibilityIdentifier("route-day-picker")
                }
                .transaction { $0.animation = nil }
            }
        }
    }
}
