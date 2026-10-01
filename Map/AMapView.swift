import SwiftUI
import CoreLocation
import QuartzCore

#if !targetEnvironment(simulator)
struct AMapNativeRenderer: UIViewRepresentable {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeUIView(context: Context) -> MAMapView {
        AMapBootstrap.configure(settings)
        let map = MAMapView(frame: .zero)
        map.delegate = context.coordinator; map.zoomLevel = 13; map.isShowsIndoorMap = false
        map.showsCompass = false; map.showsScale = true
        map.centerCoordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        context.coordinator.map = map
        return map
    }
    func updateUIView(_ map: MAMapView, context: Context) { context.coordinator.update(map) }
    static func dismantleUIView(_ map: MAMapView, coordinator: Coordinator) {
        coordinator.cancelRouteUpdates()
        map.delegate = nil; map.showsUserLocation = false
    }
    final class Pin: MAPointAnnotation {
        let markerID: String
        var marker: Marker
        init(_ marker: Marker) { self.markerID = marker.id; self.marker = marker; super.init(); update(marker) }
        func update(_ marker: Marker) {
            self.marker = marker; let p = Coordinates.gcj(marker.coordinates)
            coordinate = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude); title = marker.title
        }
    }
    final class SearchPin: MAPointAnnotation {
        var place: Place
        var number: Int
        init(place: Place, number: Int) {
            self.place = place; self.number = number; super.init(); update(place: place, number: number)
        }
        func update(place: Place, number: Int) {
            self.place = place; self.number = number
            let p = Coordinates.gcj(place.coordinates)
            coordinate = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
            title = place.name
        }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency MAMapViewDelegate {
        let store: AppStore
        weak var map: MAMapView?
        var pins: [String: Pin] = [:]
        var searchPins: [String: SearchPin] = [:]
        var lines: [String: (MAPolyline, MAPolyline)] = [:]
        var overlayStyle: [ObjectIdentifier: (UIColor, Bool)] = [:]
        var lastRoutes: [String: RouteOverlayGeometry] = [:]
        private let routeProcessing = RouteProcessing()
        private var coordinateTask: Task<Void, Never>?
        private var desiredRoutes: [RouteOverlayGeometry] = []
        private var routeRevision = UUID()
        var lastCamera: UUID?
        var lastLocate: UUID?
        var routesVisible = true
        var lastStyledCompact: Bool?
        var lastStyledSelection: String?
        var pinImages: [String: UIImage] = [:]
        init(_ store: AppStore) { self.store = store }
        func update(_ map: MAMapView) {
            let wanted = Set(store.mapMarkers.map(\.id))
            for id in Array(pins.keys) where !wanted.contains(id) { if let pin = pins.removeValue(forKey: id) { map.removeAnnotation(pin) } }
            for marker in store.mapMarkers {
                if let pin = pins[marker.id] {
                    if pin.marker != marker {
                        pin.update(marker)
                        if let view = map.view(for: pin) { style(view, pin: pin, map: map) }
                    }
                }
                else { let pin = Pin(marker); pins[marker.id] = pin; map.addAnnotation(pin) }
            }
            let wantedSearch = Set(store.searchResults.map(\.id))
            for id in Array(searchPins.keys) where !wantedSearch.contains(id) {
                if let pin = searchPins.removeValue(forKey: id) { map.removeAnnotation(pin) }
            }
            for (index, place) in store.searchResults.enumerated() {
                if let pin = searchPins[place.id] { pin.update(place: place, number: index + 1) }
                else {
                    let pin = SearchPin(place: place, number: index + 1)
                    searchPins[place.id] = pin; map.addAnnotation(pin)
                }
                if let pin = searchPins[place.id], let view = map.view(for: pin) { styleSearch(view, pin: pin) }
            }
            updateZoomPresentation(map)
            updateRoutes(map)
            if let command = store.camera, lastCamera != command.id {
                lastCamera = command.id
                let coords = command.points.map { p -> CLLocationCoordinate2D in
                    let gcj = Coordinates.gcj(p); return CLLocationCoordinate2D(latitude: gcj.latitude, longitude: gcj.longitude)
                }
                if coords.count == 1 {
                    let insets = padding(map)
                    let status = map.getMapStatus()!
                    status.centerCoordinate = coords[0]
                    status.zoomLevel = CGFloat(command.zoomLevel ?? 15)
                    status.screenAnchor = CGPoint(
                        x: (map.bounds.width + insets.left - insets.right) / (2 * max(1, map.bounds.width)),
                        y: (map.bounds.height + insets.top - insets.bottom) / (2 * max(1, map.bounds.height)))
                    let duration = CameraMotion.duration(
                        from: Coordinates.wgs(Coordinate(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)),
                        to: command.points[0], currentZoom: Double(map.zoomLevel), targetZoom: command.zoomLevel,
                        reduceMotion: UIAccessibility.isReduceMotionEnabled)
                    withCameraAnimation(duration: duration) {
                        map.setMapStatus(status, animated: duration > 0, duration: duration)
                    }
                } else if let first = coords.first {
                    map.screenAnchor = CGPoint(x: 0.5, y: 0.5)
                    var rect = MAMapRectMake(MAMapPointForCoordinate(first).x, MAMapPointForCoordinate(first).y, 1, 1)
                    for p in coords { let point = MAMapPointForCoordinate(p); rect = MAMapRectUnion(rect, MAMapRectMake(point.x, point.y, 1, 1)) }
                    let center = MACoordinateForMapPoint(MAMapPointMake(rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2))
                    let duration = CameraMotion.duration(
                        from: Coordinates.wgs(Coordinate(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)),
                        to: Coordinates.wgs(Coordinate(latitude: center.latitude, longitude: center.longitude)),
                        currentZoom: Double(map.zoomLevel), targetZoom: nil, fitting: true,
                        reduceMotion: UIAccessibility.isReduceMotionEnabled)
                    withCameraAnimation(duration: duration) {
                        map.setVisibleMapRect(rect, edgePadding: padding(map), animated: duration > 0, duration: duration)
                    }
                }
            }
            updatePinStyles(map)
            if lastLocate == nil { lastLocate = store.locating }
            else if lastLocate != store.locating {
                lastLocate = store.locating; map.showsUserLocation = true
                map.setUserTrackingMode(.follow, animated: true)
            }
        }
        private func padding(_ map: MAMapView) -> UIEdgeInsets {
            let insets = store.mapViewportInsets
            return UIEdgeInsets(top: insets.top, left: insets.left, bottom: min(insets.bottom, map.bounds.height * 0.48), right: insets.right)
        }
        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            if let pin = annotation as? SearchPin {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "search-result") ?? MAAnnotationView(annotation: pin, reuseIdentifier: "search-result")!
                view.annotation = pin; view.canShowCallout = false
                styleSearch(view, pin: pin)
                return view
            }
            guard let pin = annotation as? Pin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "marker") ?? MAAnnotationView(annotation: pin, reuseIdentifier: "marker")!
            view.annotation = pin; view.canShowCallout = false
            style(view, pin: pin, map: mapView)
            return view
        }
        private func withCameraAnimation(duration: TimeInterval, changes: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(duration == 0)
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            changes()
            CATransaction.commit()
        }

        func cancelRouteUpdates() {
            routeRevision = UUID(); coordinateTask?.cancel(); coordinateTask = nil
        }

        private func updateRoutes(_ map: MAMapView) {
            let snapshot = store.displayRoutes.map(RouteOverlayGeometry.init)
            guard snapshot != desiredRoutes else { return }
            desiredRoutes = snapshot
            cancelRouteUpdates()
            let revision = routeRevision
            let changed = snapshot.filter { lastRoutes[$0.id] != $0 }
            let processor = routeProcessing
            coordinateTask = Task { [weak self, weak map] in
                guard let prepared = try? await processor.amapSnapshot(changed), !Task.isCancelled,
                      let self, let map, self.routeRevision == revision,
                      self.store.displayRoutes.map(RouteOverlayGeometry.init) == snapshot else { return }
                // Keep the old complete picture while converting. Commit removals, new
                // geometry, both strokes and renderer invalidation in one UI turn.
                CATransaction.begin(); CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    let wanted = Set(snapshot.map(\.id))
                    var removed: [MAPolyline] = []
                    for id in Array(self.lines.keys) where !wanted.contains(id) {
                        if let (white, colored) = self.lines.removeValue(forKey: id) {
                            removed += [white, colored]
                            self.overlayStyle.removeValue(forKey: ObjectIdentifier(white))
                            self.overlayStyle.removeValue(forKey: ObjectIdentifier(colored))
                        }
                        self.lastRoutes.removeValue(forKey: id)
                    }
                    if !removed.isEmpty { map.removeOverlays(removed) }
                    var added: [MAPolyline] = []
                    for route in prepared { added += self.applyRoute(route, map: map) }
                    if self.routesVisible && !added.isEmpty { map.addOverlays(added) }
                }
                CATransaction.commit()
                self.coordinateTask = nil
            }
        }

        private func applyRoute(_ prepared: PreparedRouteOverlay, map: MAMapView) -> [MAPolyline] {
            let route = prepared.geometry
            var coordinates = prepared.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            guard coordinates.count > 1 else { return [] }
            let tint = UIColor(Theme.color(route.colorIndex))
            var added: [MAPolyline] = []
            if let (white, colored) = lines[route.id] {
                if lastRoutes[route.id]?.points != route.points {
                    white.setPolylineWithCoordinates(&coordinates, count: coordinates.count)
                    colored.setPolylineWithCoordinates(&coordinates, count: coordinates.count)
                }
                overlayStyle[ObjectIdentifier(colored)] = (tint, false)
                // The SDK requires renderer invalidation when its overlay model changes.
                map.renderer(for: white)?.setNeedsUpdate()
                if let renderer = map.renderer(for: colored) as? MAPolylineRenderer {
                    renderer.strokeColor = tint; renderer.setNeedsUpdate()
                }
            } else {
                guard let white = MAPolyline(coordinates: &coordinates, count: UInt(coordinates.count)),
                      let colored = MAPolyline(coordinates: &coordinates, count: UInt(coordinates.count)) else { return [] }
                overlayStyle[ObjectIdentifier(white)] = (.white, true)
                overlayStyle[ObjectIdentifier(colored)] = (tint, false)
                lines[route.id] = (white, colored)
                added = [white, colored]
            }
            lastRoutes[route.id] = route
            return added
        }
        private func styleSearch(_ view: MAAnnotationView, pin: SearchPin) {
            let selected = store.selectedSearchPlaceID == pin.place.id
            let key = "search-\(pin.number)-\(selected)"
            if pinImages[key] == nil { pinImages[key] = SearchPinAppearance.image(number: pin.number, selected: selected) }
            view.image = pinImages[key]; view.centerOffset = CGPoint(x: 0, y: -22)
            view.isAccessibilityElement = true; view.accessibilityLabel = "搜索结果\(pin.number)：\(pin.place.name)"
            view.accessibilityIdentifier = "map-search-result-\(pin.place.id)"
        }
        private func markerImage(_ pin: Pin, dot: Bool, selected: Bool) -> UIImage {
            let key = "\(pin.marker.icon.rawValue)-\(dot)-\(selected)"
            if let image = pinImages[key] { return image }
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44))
            let image = renderer.image { context in
                let cg = context.cgContext
                let rgb: UInt32 = selected ? 0x2563EB : pin.marker.icon.colorRGB
                let color = UIColor(red: CGFloat((rgb >> 16) & 255)/255,
                                    green: CGFloat((rgb >> 8) & 255)/255, blue: CGFloat(rgb & 255)/255,
                                    alpha: selected ? 1 : 0.75)
                let diameter: CGFloat = dot ? 10 : selected ? 30.8 : 28
                let circle = CGRect(x: (44-diameter)/2, y: (44-diameter)/2, width: diameter, height: diameter)
                cg.saveGState()
                if !dot { cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.18).cgColor) }
                cg.setFillColor(color.cgColor); cg.fillEllipse(in: circle)
                cg.restoreGState()
                cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(dot ? 1 : 2)
                cg.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
                if selected && !dot {
                    cg.setStrokeColor(color.cgColor); cg.setLineWidth(2)
                    cg.strokeEllipse(in: circle.insetBy(dx: -3, dy: -3))
                }
                if !dot {
                    let text = pin.marker.icon.emoji as NSString
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
                    let size = text.size(withAttributes: attrs)
                    text.draw(at: CGPoint(x: (44-size.width)/2, y: (44-size.height)/2), withAttributes: attrs)
                }
            }
            pinImages[key] = image
            return image
        }
        private func style(_ view: MAAnnotationView, pin: Pin, map: MAMapView) {
            let compact = MapZoomPresentation.isCompact(Double(map.zoomLevel))
            let selected = store.selectedMarker?.id == pin.markerID
            let image = markerImage(pin, dot: false, selected: selected)
            if view.image !== image { view.image = image }
            view.centerOffset = .zero
            let dotView: UIImageView
            if let existing = view.viewWithTag(48276) as? UIImageView { dotView = existing }
            else {
                dotView = UIImageView(frame: view.bounds)
                dotView.tag = 48276; dotView.isUserInteractionEnabled = false
                dotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(dotView)
            }
            let dotImage = markerImage(pin, dot: true, selected: selected)
            if dotView.image !== dotImage { dotView.image = dotImage }
            let mode = compact ? 1 : 2
            let animate = view.tag != 0 && view.tag != mode && !UIAccessibility.isReduceMotionEnabled
            if view.tag != mode {
                let changes = {
                    view.imageView.transform = compact ? CGAffineTransform(scaleX: 10.0/28.0, y: 10.0/28.0) : .identity
                    view.imageView.alpha = compact ? 0 : 1
                    dotView.transform = compact ? .identity : CGAffineTransform(scaleX: 2.8, y: 2.8)
                    dotView.alpha = compact ? 1 : 0
                }
                if animate {
                    UIView.animate(withDuration: MapZoomPresentation.transitionDuration, delay: 0,
                                   options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: changes)
                } else { UIView.performWithoutAnimation(changes) }
                view.tag = mode
            }
            view.isAccessibilityElement = true; view.accessibilityLabel = pin.marker.title
            view.accessibilityIdentifier = "map-marker-\(pin.markerID)"
        }
        private func updateZoomPresentation(_ map: MAMapView) {
            updatePinStyles(map)
            let visible = !MapZoomPresentation.isCompact(Double(map.zoomLevel))
            guard visible != routesVisible else { return }
            routesVisible = visible
            let overlays = lines.values.flatMap { [$0.0, $0.1] }
            if visible { map.addOverlays(overlays) } else { map.removeOverlays(overlays) }
        }
        func mapViewRegionChanged(_ mapView: MAMapView!) {
            updateZoomPresentation(mapView)
        }
        private func updatePinStyles(_ map: MAMapView) {
            let compact = MapZoomPresentation.isCompact(Double(map.zoomLevel))
            let selected = store.selectedMarker?.id
            guard lastStyledCompact != compact || lastStyledSelection != selected else { return }
            let changedZoom = lastStyledCompact != compact
            let previous = lastStyledSelection
            lastStyledCompact = compact; lastStyledSelection = selected
            for pin in pins.values where changedZoom || pin.markerID == previous || pin.markerID == selected {
                if let view = map.view(for: pin) { style(view, pin: pin, map: map) }
            }
        }
        func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
            guard let line = overlay as? MAPolyline, let style = overlayStyle[ObjectIdentifier(line)] else { return nil }
            let renderer = MAPolylineRenderer(polyline: line)!
            renderer.strokeColor = style.0; renderer.lineWidth = style.1 ? 6 : 3.5
            return renderer
        }
        func mapView(_ mapView: MAMapView!, didSelect view: MAAnnotationView!) {
            if let pin = view.annotation as? SearchPin {
                store.choose(pin.place, fromMap: true); mapView.deselectAnnotation(pin, animated: false)
            } else if let pin = view.annotation as? Pin {
                store.focus(pin.marker); mapView.deselectAnnotation(pin, animated: false)
            }
        }
        func mapView(_ mapView: MAMapView!, didLongPressedAt coordinate: CLLocationCoordinate2D) {
            store.create(at: Coordinates.wgs(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)))
        }
        func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
            guard !MapZoomPresentation.isCompact(Double(mapView.zoomLevel)) else { return }
            let tap = mapView.convert(coordinate, toPointTo: mapView)
            let candidates = store.displayRoutes.map { route -> (DisplayRoute, Double) in
                let path = route.points.map { point -> (Double, Double) in
                    let p = Coordinates.gcj(point)
                    let screen = mapView.convert(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude), toPointTo: mapView)
                    return (screen.x, screen.y)
                }
                return (route, RouteGeometry.nearestDistance((tap.x, tap.y), to: path))
            }.filter { $0.1 <= 14 }.sorted { $0.1 < $1.1 }
            guard !candidates.isEmpty else { return }
            let near = candidates.filter { $0.1 <= candidates[0].1 + 2 }
            let unique = Dictionary(grouping: near, by: { $0.0.dayID }).values.compactMap { $0.first?.0 }.sorted { $0.dayID < $1.dayID }
            if unique.count > 1 { store.routeCandidates = unique }
            else if let first = unique.first { store.selectRoute(first) }
        }
        func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool) {
            updateZoomPresentation(mapView)
            let rect = mapView.bounds
            let nw = mapView.convert(CGPoint(x: rect.minX, y: rect.minY), toCoordinateFrom: mapView)
            let se = mapView.convert(CGPoint(x: rect.maxX, y: rect.maxY), toCoordinateFrom: mapView)
            let a = Coordinates.wgs(Coordinate(latitude: nw.latitude, longitude: nw.longitude)), b = Coordinates.wgs(Coordinate(latitude: se.latitude, longitude: se.longitude))
            store.bounds = SearchBounds(west: min(a.longitude,b.longitude), south: min(a.latitude,b.latitude), east: max(a.longitude,b.longitude), north: max(a.latitude,b.latitude))
        }
    }
}
#endif

// Deliberately labeled preview, not a replacement map provider or production SDK verification.
struct PreviewMap: View {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewZoom = ProcessInfo.processInfo.arguments.contains("--compact-map-demo") ? 9.0 : 13.0
    @GestureState private var magnification = 1.0
    private var zoom: Double { previewZoom + log2(max(0.01, magnification)) }
    func point(_ p: Coordinate, size: CGSize) -> CGPoint {
        let insets = store.mapViewportInsets
        let usableWidth = max(80, size.width - insets.left - insets.right)
        let usableHeight = max(80, size.height - insets.top - insets.bottom)
        return CGPoint(x: insets.left + (p.longitude - 121.432) * usableWidth / 0.018,
                       y: insets.top + (31.229 - p.latitude) * usableHeight / 0.029)
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.90, green: 0.94, blue: 0.96)))
                    for i in 0..<13 {
                        var path = Path(); let x = CGFloat(i)*48-120
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x+230, y: size.height))
                        context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 12)
                    }
                    for i in 0..<10 {
                        var path = Path(); let y = CGFloat(i)*84
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y-80))
                        context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 10)
                    }
                    for route in MapZoomPresentation.isCompact(zoom) ? [] : store.displayRoutes {
                        var path = Path(); for (index, p) in route.points.enumerated() {
                            let pt = point(p, size: size); if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        context.stroke(path, with: .color(Theme.color(route.colorIndex)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }
                ForEach(store.mapMarkers) { marker in
                    Button { store.focus(marker) } label: {
                        MapMarkerCircle(icon: marker.icon, selected: store.selectedMarker?.id == marker.id,
                                        compact: MapZoomPresentation.isCompact(zoom))
                            .animation(reduceMotion ? nil : .easeOut(duration: MapZoomPresentation.transitionDuration), value: MapZoomPresentation.isCompact(zoom))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel(marker.title).accessibilityIdentifier("map-marker-\(marker.id)")
                        .accessibilityValue(MapZoomPresentation.isCompact(zoom) ? "圆点" : "图标")
                        .position(point(marker.coordinates, size: proxy.size))
                }
                ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, place in
                    Button { store.choose(place, fromMap: true) } label: {
                        Image(uiImage: SearchPinAppearance.image(number: index + 1, selected: store.selectedSearchPlaceID == place.id))
                            .frame(width: 44, height: 48)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("搜索结果\(index + 1)：\(place.name)")
                        .accessibilityIdentifier("map-search-result-\(place.id)")
                        .position(point(place.coordinates, size: proxy.size))
                        .offset(y: -22)
                }
                Text("模拟器 · 交互预览画布").font(.caption2).foregroundStyle(.secondary)
                    .padding(6).background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, store.mapViewportInsets.bottom+12).padding(.leading, store.mapViewportInsets.left+8)
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("preview-map-surface")
            .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in
                state = value.magnification
            }.onEnded { value in
                previewZoom = min(20, max(3, previewZoom + log2(max(0.01, value.magnification))))
            })
            .onLongPressGesture {
                store.create(at: Coordinate(latitude: 31.219, longitude: 121.443))
            }
        }
    }
}
