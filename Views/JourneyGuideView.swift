import SwiftUI
import MapKit

/// An isolated map with local place details; selection leaves the live map camera unchanged.
struct JourneyGuideView: View {
    let store: AppStore
    let trip: Trip
    let markers: [Marker]
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [DisplayRoute]?
    @State private var selectedDayID: String?
    @State private var error: String?
    @State private var selectedMarker: Marker?
    private var days: [TripDay] { trip.days.sorted { ($0.date, $0.id) < ($1.date, $1.id) } }
    private var scopeTrip: Trip {
        var copy = trip
        if let selectedDayID { copy.days = days.filter { $0.id == selectedDayID } }
        return copy
    }
    private var scopeTitle: String {
        guard let index = days.firstIndex(where: { $0.id == selectedDayID }) else { return "全程导览" }
        return "第\(index + 1)天 · \(days[index].date)"
    }
    var body: some View {
        NavigationStack {
            Group {
                if let routes {
                    JourneyGuideMap(trip: scopeTrip, markers: markers,
                        routes: routes.filter { selectedDayID == nil || $0.dayID == selectedDayID },
                        dayNumbers: Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.id, $0.offset + 1) }),
                        onSelect: { selectedMarker = $0 })
                        .id(selectedDayID ?? "whole-trip")
                        .ignoresSafeArea()
                }
                else if let error { ContentUnavailableView("无法生成导览", systemImage: "map", description: Text(error)) }
                else { ProgressView("正在准备全程导览…") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.95), location: 0),
                        .init(color: .white.opacity(0.85), location: 0.45),
                        .init(color: .white.opacity(0.35), location: 0.75),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.safeAreaInsets.top + 100)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }.allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 20))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("关闭")
                    Spacer(minLength: 0)
                    Menu {
                        Button("全程导览") { selectedDayID = nil }
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            Button("第\(index + 1)天 · \(day.date)") { selectedDayID = day.id }
                        }
                    } label: {
                        HStack(spacing: 5) { Text(scopeTitle).font(.headline); Image(systemName: "chevron.down").font(.caption) }
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("guide-scope-menu")
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 44, height: 44).allowsHitTesting(false)
                }
                .buttonStyle(.plain).foregroundStyle(.black).tint(.black)
                .padding(.horizontal, 16)
            }
            .sheet(item: $selectedMarker) { marker in
                MarkerDetailView(store: store, marker: marker, usesDayContext: false, noteTripID: trip.id,
                    onClose: { selectedMarker = nil }, onNavigateItinerary: { selectedMarker = nil })
            }
            .task {
                do {
                    let result = try await store.guideRoutes(trip: trip, markers: markers)
                    try Task.checkCancellation(); routes = result
                } catch is CancellationError {} catch { self.error = "请重新打开后重试。" }
            }
        }
    }
}

private struct JourneyGuideMap: UIViewRepresentable {
    let trip: Trip
    let markers: [Marker]
    let routes: [DisplayRoute]
    let dayNumbers: [String: Int]
    let onSelect: (Marker) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(trip: trip, markers: markers, routes: routes, dayNumbers: dayNumbers, onSelect: onSelect) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false; map.isPitchEnabled = false
        map.accessibilityIdentifier = "journey-guide-map"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.install(map)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {}
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.layoutTask?.cancel(); coordinator.layoutGeneration = UUID(); map.delegate = nil
    }

    final class PinView: MKAnnotationView {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool {
            guard let activate else { return false }
            activate(); return true
        }
    }
    final class Line: MKPolyline { var color = UIColor.systemBlue }
    final class Pin: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let marker: Marker
        init(_ marker: Marker) {
            self.marker = marker
            coordinate = CLLocationCoordinate2D(latitude: marker.coordinates.latitude, longitude: marker.coordinates.longitude)
        }
    }
    struct Visit {
        let day: Int
        let date: String
        let time: String?
        let duration: Int?
        let note: String?
        let color: UIColor
    }
    struct Card {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let visits: [Visit]
        var subtitle: String = ""
        var emoji: String? = nil
        let color: UIColor
        var routeID: String? = nil
        var icon: String = "mappin"
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let trip: Trip
        let markers: [Marker]
        let routes: [DisplayRoute]
        let dayNumbers: [String: Int]
        let onSelect: (Marker) -> Void
        var cards: [(Card, UIView)] = []
        var leaders = CAShapeLayer()
        var fit = MKMapRect.null
        var fitted = false
        let solver = ItineraryCardLayout()
        /// Card centres pinned to the map; cards keep their size while the camera moves.
        var pinned: [String: CLLocationCoordinate2D] = [:]
        var overview: [String: CLLocationCoordinate2D] = [:]
        var overviewDistance: CLLocationDistance = 0
        var anchors: [String: CLLocationCoordinate2D] = [:]
        var leaderLayers: [String: [CAShapeLayer]] = [:]
        var layoutTask: Task<Void, Never>?
        var layoutGeneration = UUID()
        var layoutErrorReported = false
        init(trip: Trip, markers: [Marker], routes: [DisplayRoute], dayNumbers: [String: Int], onSelect: @escaping (Marker) -> Void) {
            self.trip = trip; self.markers = markers; self.routes = routes; self.dayNumbers = dayNumbers
            self.onSelect = onSelect
        }
        func install(_ map: MKMapView) {
            let days = trip.days.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
            let ids = Set(days.flatMap { $0.markerIds + $0.chains.flatMap { $0 } })
            let places = markers.filter { ids.contains($0.id) && $0.coordinates.isValid }
            let lookup = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            map.addAnnotations(places.map(Pin.init))
            for route in routes {
                var points = route.points.filter(\.isValid).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                guard points.count > 1 else { continue }
                let line = Line(coordinates: &points, count: points.count)
                line.color = RouteLineAppearance.color(route.colorIndex)
                map.addOverlay(line)
                fit = fit.union(line.boundingMapRect)
            }
            for place in places {
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: place.coordinates.latitude, longitude: place.coordinates.longitude))
                fit = fit.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
            }
            var merged: [String: (Marker, [Visit], UIColor)] = [:]
            for (index, day) in days.enumerated() {
                let color = RouteLineAppearance.color(day.colorIndex ?? index)
                let validRoutes = day.chains.indices.compactMap { day.scheduledRoute(at: $0) }
                let stops = validRoutes.flatMap(\.stops).filter { $0.isHighlight == true }
                var visited = Set<String>()
                for stop in stops where visited.insert(stop.markerId).inserted {
                    guard let marker = lookup[stop.markerId] else { continue }
                    let detail = Visit(day: dayNumbers[day.id] ?? index + 1, date: day.date, time: stop.startTime, duration: stop.durationMinutes, note: stop.note, color: color)
                    if var current = merged[marker.id] { current.1.append(detail); merged[marker.id] = current }
                    else { merged[marker.id] = (marker, [detail], color) }
                }
                for route in validRoutes {
                    for leg in route.legs where leg.isHighlight == true {
                        guard let from = route.stops.first(where: { $0.id == leg.fromStopId }).flatMap({ lookup[$0.markerId] }),
                              let to = route.stops.first(where: { $0.id == leg.toStopId }).flatMap({ lookup[$0.markerId] }) else { continue }
                        let coordinate = CLLocationCoordinate2D(latitude: (from.coordinates.latitude + to.coordinates.latitude) / 2, longitude: (from.coordinates.longitude + to.coordinates.longitude) / 2)
                        let chainIndex = day.routeChains?.firstIndex(where: { $0.id == route.id }) ?? 0
                        let stopIndex = route.stops.firstIndex(where: { $0.id == leg.fromStopId }) ?? 0
                        let routeID = "\(day.id)|\(chainIndex)|\(stopIndex + 1)|\(from.id)|\(to.id)"
                        add(Card(id: "leg:\(day.id):\(leg.fromStopId):\(leg.toStopId)", coordinate: coordinate, title: leg.serviceNumber?.isEmpty == false ? leg.serviceNumber! : leg.mode.label,
                            visits: [Visit(day: dayNumbers[day.id] ?? index + 1, date: day.date, time: leg.startTime, duration: leg.durationMinutes, note: leg.note, color: color)], subtitle: "\(leg.mode.label) · \(from.content.title ?? "未命名地点") → \(to.content.title ?? "未命名地点")", color: color, routeID: routeID, icon: leg.mode.symbol), to: map)
                    }
                }
            }
            for id in merged.keys.sorted() {
                guard let (marker, details, color) = merged[id] else { continue }
                add(Card(id: "place:" + marker.id, coordinate: CLLocationCoordinate2D(latitude: marker.coordinates.latitude, longitude: marker.coordinates.longitude), title: trip.displayTitle(for: marker), visits: details, emoji: marker.icon.emoji, color: color, icon: marker.icon.symbol), to: map)
            }
            leaders.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.7).cgColor
            leaders.fillColor = UIColor.clear.cgColor; leaders.lineWidth = 1
            map.layer.addSublayer(leaders)
        }
        func add(_ card: Card, to map: MKMapView) {
            func label(_ text: String, size: CGFloat, color: UIColor = .label, weight: UIFont.Weight = .regular, lines: Int = 1) -> UILabel {
                let view = UILabel(); view.text = text; view.font = .systemFont(ofSize: size, weight: weight)
                view.textColor = color; view.numberOfLines = lines; view.lineBreakMode = .byTruncatingTail
                return view
            }
            func stack(_ axis: NSLayoutConstraint.Axis, spacing: CGFloat) -> UIStackView {
                let view = UIStackView(); view.axis = axis; view.spacing = spacing; return view
            }
            let box = UIView(); box.backgroundColor = .white
            box.layer.cornerRadius = 12
            box.layer.borderColor = UIColor(white: 0.88, alpha: 0.8).cgColor; box.layer.borderWidth = 1
            box.layer.shadowColor = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1).cgColor
            box.layer.shadowOpacity = 0.08; box.layer.shadowRadius = 10; box.layer.shadowOffset = CGSize(width: 0, height: 4)
            box.isUserInteractionEnabled = false
            let content = stack(.vertical, spacing: 6)
            let header = stack(.horizontal, spacing: 7); header.alignment = .top
            let icon = UIView(); icon.backgroundColor = card.color.withAlphaComponent(0.14); icon.layer.cornerRadius = 8
            icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let artwork: UIView
            if let emoji = card.emoji, let name = PlaceIconAssets.name(for: emoji), let image = UIImage(named: name) {
                let imageView = UIImageView(image: image); imageView.contentMode = .scaleAspectFit; artwork = imageView
            } else {
                let imageView = UIImageView(image: UIImage(systemName: card.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
                imageView.tintColor = card.color; imageView.contentMode = .scaleAspectFit; artwork = imageView
            }
            icon.addSubview(artwork); artwork.frame = CGRect(x: 3, y: 3, width: 16, height: 16)
            let identity = stack(.vertical, spacing: 2)
            let titleRow = stack(.horizontal, spacing: 6); titleRow.alignment = .top
            titleRow.addArrangedSubview(label(card.title, size: 13, weight: .semibold, lines: 2))
            if trip.days.count > 1, card.visits.count == 1, let visit = card.visits.first {
                let day = label("第\(visit.day)天", size: 11, color: visit.color, weight: .semibold)
                day.setContentCompressionResistancePriority(.required, for: .horizontal)
                day.setContentHuggingPriority(.required, for: .horizontal)
                titleRow.addArrangedSubview(day)
            }
            identity.addArrangedSubview(titleRow)
            if !card.subtitle.isEmpty { identity.addArrangedSubview(label(card.subtitle, size: 11, color: .secondaryLabel, lines: 2)) }
            header.addArrangedSubview(icon); header.addArrangedSubview(identity); content.addArrangedSubview(header)
            for (index, visit) in card.visits.enumerated() {
                if index > 0 {
                    let separator = UIView(); separator.backgroundColor = UIColor(white: 0.94, alpha: 1)
                    separator.heightAnchor.constraint(equalToConstant: 1).isActive = true; content.addArrangedSubview(separator)
                }
                let section = stack(.vertical, spacing: 6)
                var metadata: [String] = []
                if trip.days.count > 1 {
                    if card.visits.count > 1 { metadata.append("第\(visit.day)天") }
                    let parts = visit.date.split(separator: "-")
                    metadata.append(parts.count == 3 ? "\(Int(parts[1]) ?? 0)月\(Int(parts[2]) ?? 0)日" : visit.date)
                }
                if let time = visit.time, !time.isEmpty { metadata.append(time) }
                if let minutes = visit.duration { metadata.append(RouteScheduleText.duration(minutes)) }
                if !metadata.isEmpty {
                    let text = label(metadata.joined(separator: " · "), size: 11, color: .secondaryLabel, lines: 2)
                    if card.visits.count == 1 { identity.addArrangedSubview(text) }
                    else { section.addArrangedSubview(text) }
                }
                if let note = visit.note, !note.isEmpty {
                    section.addArrangedSubview(label(note, size: 12, color: .secondaryLabel, lines: 3))
                }
                if section.arrangedSubviews.isEmpty { continue }
                content.addArrangedSubview(section)
            }
            box.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10), content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10), content.topAnchor.constraint(equalTo: box.topAnchor, constant: 8), content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8)])
            let natural = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 20
            let width = min(220, max(150, natural))
            let size = box.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            box.frame.size = CGSize(width: width, height: size.height)
            box.layoutIfNeeded()
            box.alpha = 0; box.isHidden = true
            map.addSubview(box); cards.append((card, box))
        }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard !fitted, mapView.bounds.width > 0, !fit.isNull else { return }
            fitted = true
            let bounds = fit.insetBy(dx: -max(fit.width * 0.1, 1500), dy: -max(fit.height * 0.1, 1500))
            mapView.setVisibleMapRect(bounds, edgePadding: UIEdgeInsets(top: 90, left: 55, bottom: 90, right: 55), animated: false)
            layout(mapView)
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            layoutTask?.cancel(); layoutGeneration = UUID()
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            project(mapView)
            if fitted { layout(mapView) }
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { project(mapView) }
        private func layoutArea(_ map: MKMapView) -> CGRect {
            map.bounds.inset(by: UIEdgeInsets(top: max(90, map.safeAreaInsets.top + 56), left: 12, bottom: max(24, map.safeAreaInsets.bottom + 12), right: 12))
        }
        private func anchorPoint(_ card: Card, _ map: MKMapView) -> CGPoint {
            var p = map.convert(card.coordinate, toPointTo: map)
            if let id = card.routeID, let route = routes.first(where: { $0.id == id }) {
                let projected = route.points.filter(\.isValid).map {
                    map.convert(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), toPointTo: map)
                }
                let lengths = zip(projected, projected.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
                var remaining = lengths.reduce(0, +) / 2
                for (index, length) in lengths.enumerated() {
                    if remaining <= length, length > 0 {
                        let a = projected[index], b = projected[index + 1], t = remaining / length
                        p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t); break
                    }
                    remaining -= length
                }
            }
            return p
        }
        /// Cards follow the map during gestures and keep their pinned layout. After the camera settles, a new layout is
        /// only computed when the set of anchors on screen changes; zooming alone never relayouts. The overview layout
        /// is reused when every anchor is back on screen at the overview zoom.
        func layout(_ map: MKMapView) {
            layoutTask?.cancel()
            let generation = UUID(); layoutGeneration = generation
            let first = overviewDistance == 0
            if first {
                for (card, _) in cards { anchors[card.id] = map.convert(anchorPoint(card, map), toCoordinateFrom: map) }
            }
            let area = layoutArea(map)
            let input: [ItineraryLayoutAnchor] = cards.compactMap { card, box in
                guard let coordinate = anchors[card.id] else { return nil }
                let p = map.convert(coordinate, toPointTo: map)
                guard first || area.contains(p) else { return nil }
                return ItineraryLayoutAnchor(id: card.id, x: p.x, y: p.y, width: box.bounds.width, height: box.bounds.height)
            }
            if !first {
                let ids = Set(input.map(\.id))
                if ids == Set(pinned.keys) { return }
                if ids == Set(overview.keys), map.camera.centerCoordinateDistance >= overviewDistance * 0.98 {
                    apply(overview, map); return
                }
            }
            let previous: [ItineraryLayoutPlacement] = input.compactMap { anchor in
                guard let center = pinned[anchor.id] else { return nil }
                let c = map.convert(center, toPointTo: map)
                let left = c.x - anchor.width / 2, top = c.y - anchor.height / 2
                return ItineraryLayoutPlacement(id: anchor.id, x: anchor.x, y: anchor.y, width: anchor.width, height: anchor.height, left: left, top: top,
                                                end: ItineraryCardLayout.leaderEnd(left: left, top: top, width: anchor.width, height: anchor.height, anchor: ItineraryLayoutPoint(x: anchor.x, y: anchor.y)))
            }
            let paths = routes.map { route in route.points.filter(\.isValid).map { point in
                let p = map.convert(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), toPointTo: map)
                return ItineraryLayoutPoint(x: p.x, y: p.y)
            } }
            let bounds = ItineraryLayoutBounds(left: area.minX, top: area.minY, right: area.maxX, bottom: area.maxY)
            layoutTask = Task { [weak self, weak map] in
                do {
                    try await Task.sleep(for: .milliseconds(first ? 180 : 250))
                    guard let self else { return }
                    let result = try await self.solver.layout(anchors: input, bounds: bounds, paths: paths, previous: previous)
                    guard !Task.isCancelled, self.layoutGeneration == generation, let map else { return }
                    // Any camera move cancels this task, so the projection used for the inputs is still current.
                    var next: [String: CLLocationCoordinate2D] = [:]
                    for p in result { next[p.id] = map.convert(CGPoint(x: p.left + p.width / 2, y: p.top + p.height / 2), toCoordinateFrom: map) }
                    if first {
                        self.overview = next; self.overviewDistance = map.camera.centerCoordinateDistance
                        map.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: self.overviewDistance)
                    }
                    self.apply(next, map)
                } catch is CancellationError {} catch {
                    if let self, !self.layoutErrorReported { self.layoutErrorReported = true; NSLog("Itinerary layout unavailable") }
                }
            }
        }
        private func layers(for card: Card) -> [CAShapeLayer] {
            if let existing = leaderLayers[card.id] { return existing }
            let layers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
            for (line, (color, width)) in zip(layers, [(UIColor.white.withAlphaComponent(0.85), 3.5), (card.color, 1.5)]) {
                line.strokeColor = color.cgColor; line.fillColor = UIColor.clear.cgColor
                line.lineWidth = width; line.lineCap = .round
            }
            layers[2].fillColor = card.color.cgColor; layers[2].strokeColor = UIColor.white.cgColor; layers[2].lineWidth = 2
            layers.forEach(leaders.addSublayer)
            leaderLayers[card.id] = layers
            return layers
        }
        /// Moves cards to a new pinned layout: leaving cards fade out, new ones fade in, kept ones glide while their
        /// leaders are hidden, then leaders are redrawn at the final positions.
        private func apply(_ next: [String: CLLocationCoordinate2D], _ map: MKMapView) {
            let reduce = UIAccessibility.isReduceMotionEnabled
            let old = pinned
            pinned = next
            var appearing: [UIView] = [], leaving: [UIView] = [], moving: [(UIView, CGPoint)] = []
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (card, box) in cards {
                let layers = layers(for: card)
                if let center = next[card.id] {
                    let target = map.convert(center, toPointTo: map)
                    if old[card.id] == nil {
                        box.isHidden = false; box.alpha = 0; box.center = target; appearing.append(box)
                        map.bringSubviewToFront(box)
                    } else if hypot(box.center.x - target.x, box.center.y - target.y) > 0.5 {
                        moving.append((box, target)); layers.forEach { $0.opacity = 0 }
                    }
                } else if old[card.id] != nil {
                    leaving.append(box); layers.forEach { $0.opacity = 0 }
                }
            }
            CATransaction.commit()
            let generation = layoutGeneration
            UIView.animate(withDuration: reduce ? 0 : 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                appearing.forEach { $0.alpha = 1 }
                leaving.forEach { $0.alpha = 0 }
                moving.forEach { $0.0.center = $0.1 }
            } completion: { [weak self, weak map] _ in
                guard let self, let map else { return }
                for (card, box) in self.cards where self.pinned[card.id] == nil && leaving.contains(where: { $0 === box }) { box.isHidden = true }
                guard self.layoutGeneration == generation else { return }
                self.project(map)
            }
            project(map, skip: Set(moving.map { ObjectIdentifier($0.0) }))
        }
        func project(_ map: MKMapView, skip: Set<ObjectIdentifier> = []) {
            guard !pinned.isEmpty else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (card, box) in cards {
                guard let layers = leaderLayers[card.id] else { continue }
                guard let center = pinned[card.id], let anchor = anchors[card.id], !skip.contains(ObjectIdentifier(box)) else {
                    if pinned[card.id] == nil { layers.forEach { $0.opacity = 0 } }
                    continue
                }
                let size = box.bounds.size
                let c = map.convert(center, toPointTo: map), a = map.convert(anchor, toPointTo: map)
                box.center = c
                let end = ItineraryCardLayout.leaderEnd(left: c.x - size.width / 2, top: c.y - size.height / 2, width: size.width, height: size.height,
                                                        anchor: ItineraryLayoutPoint(x: a.x, y: a.y))
                let path = UIBezierPath(); path.move(to: a); path.addLine(to: CGPoint(x: end.x, y: end.y))
                layers[0].path = path.cgPath; layers[1].path = path.cgPath
                layers[2].path = UIBezierPath(ovalIn: CGRect(x: a.x - 4.5, y: a.y - 4.5, width: 9, height: 9)).cgPath
                layers.forEach { $0.opacity = 1 }
            }
            CATransaction.commit()
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? Line else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = line.color
            renderer.lineWidth = 3; renderer.lineCap = .round; renderer.lineJoin = .round
            return renderer
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let hits = map.annotations.compactMap { annotation -> (Pin, CGFloat)? in
                guard let pin = annotation as? Pin, let view = map.view(for: pin),
                      !view.isHidden, view.alpha > 0 else { return nil }
                let local = view.convert(point, from: map)
                let bounds = view.bounds.insetBy(dx: min(0, (view.bounds.width - 44) / 2),
                                                dy: min(0, (view.bounds.height - 44) / 2))
                guard bounds.contains(local) else { return nil }
                return (pin, hypot(local.x - view.bounds.midX, local.y - view.bounds.midY))
            }
            if let hit = hits.min(by: { $0.1 == $1.1 ? $0.0.marker.id < $1.0.marker.id : $0.1 < $1.1 }) {
                onSelect(hit.0.marker)
            }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = PinView(annotation: pin, reuseIdentifier: nil)
            view.image = MapMarkerAppearance.image(icon: pin.marker.icon, compact: false, selected: false)
            // Keep MapKit selection out of drags; the map tap recognizer handles place selection.
            view.isEnabled = false; view.canShowCallout = false
            view.activate = { [weak self] in self?.onSelect(pin.marker) }
            view.isAccessibilityElement = true
            view.accessibilityLabel = pin.marker.title
            view.accessibilityIdentifier = "guide-marker-" + pin.marker.id
            view.accessibilityTraits = .button
            return view
        }
    }
}

#if DEBUG
struct JourneyGuideReview: View {
    let store: AppStore
    let trip: Trip
    private var fixture: Trip {
        var copy = trip
        for di in copy.days.indices {
            copy.days[di].routeChains = copy.days[di].chains.enumerated().map { ci, ids in
                let stops = ids.enumerated().map { index, id in
                    ChainStop(id: "review-\(di)-\(ci)-\(index)", markerId: id, startTime: index == 0 ? "09:30" : nil,
                        durationMinutes: index == 0 ? 60 : nil, note: index == 0 ? "只读设计样例" : nil, isHighlight: index == 0)
                }
                return RouteChain(id: "review-\(di)-\(ci)", stops: stops, legs: [])
            }
        }
        return copy
    }
    var body: some View { JourneyGuideView(store: store, trip: fixture, markers: store.markers) }
}
#endif
