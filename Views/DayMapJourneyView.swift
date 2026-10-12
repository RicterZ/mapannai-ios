import SwiftUI
import CoreLocation

struct DayMapStop: Identifiable {
    let id: String
    let marker: Marker
    let routeIndex: Int?
    let position: Int
    let visit: ChainStop?
    let leg: ChainLeg?
}
enum DayMapJourney {
    static func stops(day: TripDay, markers: [Marker]) -> [DayMapStop] {
        let lookup = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DayMapStop] = []
        for (routeIndex, ids) in day.chains.enumerated() {
            let route = day.scheduledRoute(at: routeIndex)
            for (position, id) in ids.enumerated() {
                guard let marker = lookup[id] else { continue }
                result.append(DayMapStop(id: "\(routeIndex)/\(position)/\(id)", marker: marker,
                    routeIndex: routeIndex, position: position,
                    visit: route.flatMap { $0.stops.indices.contains(position) ? $0.stops[position] : nil }, leg: route?.leg(at: position)))
            }
        }
        let routed = Set(day.chains.flatMap { $0 })
        for id in day.markerIds where !routed.contains(id) {
            guard let marker = lookup[id] else { continue }
            result.append(DayMapStop(id: "unplanned/\(id)", marker: marker, routeIndex: nil,
                position: 0, visit: nil, leg: nil))
        }
        return result
    }
    static func distance(after stop: DayMapStop, next: DayMapStop?, day: TripDay, routes: [DisplayRoute]) -> String? {
        guard let next, let index = stop.routeIndex, next.routeIndex == index,
              next.position == stop.position + 1 else { return nil }
        if let route = routes.first(where: { $0.id == "\(day.id)|\(index)|\(next.position)|\(stop.marker.id)|\(next.marker.id)" }),
           route.isPlanned, !route.isDashed, let distance = route.distance, distance.isFinite, distance > 0 {
            return formattedDistance(distance)
        }
        let start = stop.marker.coordinates, end = next.marker.coordinates
        guard start.isValid, end.isValid else { return nil }
        let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        return "直线 " + formattedDistance(distance)
    }
    private static func formattedDistance(_ distance: Double) -> String {
        distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
    }
}

struct DayMapDateStrip: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    let day: TripDay
    var identifierPrefix = "day-map-date-"
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, date in
                        Button {
                            guard date.id != day.id else { return }
                            store.select(trip: trip, day: date, focus: false)
                            store.beginDayMapBrowsing()
                        } label: {
                            HStack(spacing: 5) {
                                Text("第\(index + 1)天").font(.subheadline.weight(date.id == day.id ? .semibold : .regular))
                                Text(JourneyDayCardContent.dateFormatter.string(from: Date.fromDay(date.date))).font(.caption)
                            }.foregroundStyle(date.id == day.id ? .primary : .secondary)
                                .frame(height: 44)
                                .overlay(alignment: .bottom) {
                                    if date.id == day.id { Capsule().fill(Color.accentColor).frame(width: 18, height: 3) }
                                }
                        }.id(date.id).accessibilityIdentifier(identifierPrefix + date.id)
                    }
                }
            }.scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(day.id, anchor: .center) }
                .onChange(of: day.id) { _, id in proxy.scrollTo(id, anchor: .center) }
        }.frame(height: 44).buttonStyle(.plain)
    }
}

struct DayMapJourneyView: View {
    @ObservedObject var store: AppStore
    var showsGrabber = true
    let onClose: () -> Void
    @State private var scrolledID: String?
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var stops: [DayMapStop] { store.day.map { DayMapJourney.stops(day: $0, markers: store.markers) } ?? [] }
    var body: some View {
        VStack(spacing: 6) {
            Capsule().fill(Color(uiColor: .tertiaryLabel)).frame(width: 32, height: 4).opacity(showsGrabber ? 1 : 0).padding(.top, 4)
            HStack(spacing: 4) {
                if let trip = store.trip, let day = store.day {
                    DayMapDateStrip(store: store, trip: trip, day: day)

                }
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("关闭地图").accessibilityIdentifier("close-map-workspace")
            }.foregroundStyle(.primary).buttonStyle(.plain).padding(.horizontal, 20)
            if let day = store.day, !stops.isEmpty {
                GeometryReader { geometry in
                    let cardWidth = min(300, max(210, geometry.size.width * 0.60))
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                                HStack(spacing: 0) {
                                    placeCard(stop, number: index + 1).frame(width: index == stops.count - 1 ? max(cardWidth, geometry.size.width - 40) : cardWidth)
                                    if index + 1 < stops.count {
                                        connection(after: stop, next: stops[index + 1], day: day).frame(width: 64)
                                    }
                                }.id(stop.id)
                            }
                        }.scrollTargetLayout()
                            .padding(.trailing, 20)
                    }.contentMargins(.leading, 20, for: .scrollContent)
                        .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $scrolledID, anchor: .leading)
                        .mask { HStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 30) } }
                        .accessibilityIdentifier("day-map-chain")
                        .onChange(of: scrolledID) { _, id in
                            guard ready, let stop = stops.first(where: { $0.id == id }) else { return }
                            store.focusDayMapMarker(stop.marker.id)
                        }
                        .task(id: day.id) {
                            scrolledID = stops.first(where: { $0.marker.id == store.dayMapFocusID })?.id ?? stops.first?.id
                            await Task.yield(); ready = true
                        }
                        .onChange(of: store.dayMapFocusID) { _, id in
                            guard let stop = stops.first(where: { $0.marker.id == id }), scrolledID != stop.id else { return }
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { scrolledID = stop.id }
                        }
                }.frame(height: 86)
            } else {
                Text("这一天还没有地点").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 86)
            }
        }.padding(.bottom, 10)
            .frame(height: DayMapPresentation.contentHeight, alignment: .top)
            .background(Color(uiColor: .systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .accessibilityElement(children: .contain).accessibilityIdentifier("day-map-journey")
    }
    private func placeCard(_ stop: DayMapStop, number: Int) -> some View {
        Button {
            store.openDayMapPlaceDetails(stop.marker.id)
        } label: {
            HStack(spacing: 12) {
                DayPlaceArtwork(marker: stop.marker)
                    .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(stop.marker.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    InlinePlaceAddress(icon: stop.marker.icon, address: stop.marker.content.address ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let summary = stop.visit?.summary, !summary.isEmpty {
                        Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("day-map-stop-" + stop.marker.id)
    }
    @ViewBuilder private func connection(after stop: DayMapStop, next: DayMapStop, day: TripDay) -> some View {
        if stop.routeIndex != nil, stop.routeIndex == next.routeIndex, next.position == stop.position + 1 {
            VStack(spacing: 6) {
                if let distance = DayMapJourney.distance(after: stop, next: next, day: day, routes: store.displayRoutes) {
                    Text(distance).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                JourneyLinkArrow().stroke(Color(uiColor: .tertiaryLabel), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 8)
                if let leg = stop.leg {
                    Text(leg.mode.label).font(.system(size: 10)).foregroundStyle(.secondary)
                    if !leg.summary.isEmpty {
                        Text(leg.summary).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }.padding(.horizontal, 3).accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 24)
                Text(next.routeIndex.map { "路线 \($0 + 1)" } ?? "未安排").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
private struct JourneyLinkArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.move(to: CGPoint(x: rect.maxX - 4, y: rect.midY - 3)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY + 3))
        }
    }
}

/// An inline attachment lets line two return to the paragraph's leading edge.
private struct InlinePlaceAddress: UIViewRepresentable {
    let icon: MarkerIcon
    let address: String
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10))
        let tagFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10, weight: .medium))
        let color = UIColor(icon.themeColor).resolvedColor(with: label.traitCollection)
        let attributes: [NSAttributedString.Key: Any] = [.font: tagFont, .foregroundColor: color]
        let text = icon.label as NSString
        let textSize = text.size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 12, height: ceil(tagFont.lineHeight) + 4)
        let badge = UIGraphicsImageRenderer(size: size).image { _ in
            color.withAlphaComponent(0.12).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5).fill()
            text.draw(at: CGPoint(x: 6, y: 2), withAttributes: attributes)
        }
        let attachment = NSTextAttachment()
        attachment.image = badge
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
        let value = NSMutableAttributedString(attachment: attachment)
        value.append(NSAttributedString(string: " " + address.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]))
        label.attributedText = value
        label.accessibilityLabel = icon.label + " " + address
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
