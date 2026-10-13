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
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if date.id == day.id { Capsule().fill(Color.primary).frame(width: 18, height: 3) }
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
            if showsGrabber { Capsule().fill(Color(uiColor: .tertiaryLabel)).frame(width: 32, height: 4).padding(.top, 4) }
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
                    let cardWidth = min(210, max(164, geometry.size.width * 0.49))
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                                HStack(spacing: 0) {
                                    placeCard(stop).frame(width: index == stops.count - 1 ? max(cardWidth, geometry.size.width - 40) : cardWidth)
                                    if index + 1 < stops.count {
                                        connection(after: stop, next: stops[index + 1], day: day).frame(width: 104)
                                    }
                                }.id(stop.id)
                            }
                        }.scrollTargetLayout()
                            .padding(.trailing, 20)
                    }.contentMargins(.leading, 20, for: .scrollContent)
                        .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $scrolledID, anchor: .leading)
                        .mask {
                            HStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: scrolledID == stops.last?.id ? [.black, .black] : [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                            }
                        }
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
                }.frame(height: 66)
            } else {
                Text("这一天还没有地点").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 66)
            }
        }.padding(.top, showsGrabber ? 0 : 14).padding(.bottom, 10)
            .frame(height: DayMapPresentation.contentHeight, alignment: .top)
            .background(Color(uiColor: .systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .accessibilityElement(children: .contain).accessibilityIdentifier("day-map-journey")
    }
    private func placeCard(_ stop: DayMapStop) -> some View {
        Button {
            store.openDayMapPlaceDetails(stop.marker.id)
        } label: {
            HStack(spacing: 8) {
                PlaceIconView(emoji: stop.marker.icon.emoji, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.marker.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if let address = stop.marker.content.address, !address.isEmpty {
                        Text(address).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let visit = stop.visit, !visit.summary.isEmpty {
                        Text([visit.startTime, visit.durationMinutes.map { "停留" + RouteScheduleText.duration($0) }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 66)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5) }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("day-map-stop-" + stop.marker.id)
    }
    @ViewBuilder private func connection(after stop: DayMapStop, next: DayMapStop, day: TripDay) -> some View {
        if stop.routeIndex != nil, stop.routeIndex == next.routeIndex, next.position == stop.position + 1 {
            VStack(spacing: 6) {
                if let leg = stop.leg {
                    HStack(spacing: 3) {
                        TransportArtwork(mode: leg.mode, size: 13)
                        Text(leg.serviceNumber.flatMap { $0.isEmpty ? nil : $0 } ?? leg.mode.label)
                            .font(.caption2)
                    }
                }
                JourneyLinkArrow().stroke(Color(uiColor: .tertiaryLabel), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .frame(height: 7)
                if let leg = stop.leg, !leg.summary.isEmpty {
                    Text(leg.summary).font(.caption2).monospacedDigit()
                } else if let distance = DayMapJourney.distance(after: stop, next: next, day: day, routes: store.displayRoutes) {
                    Text(distance).font(.caption2)
                }
            }.lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
                .padding(.horizontal, 6).accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 24)
                Text(next.routeIndex.map { "路线 \($0 + 1)" } ?? "未安排").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
