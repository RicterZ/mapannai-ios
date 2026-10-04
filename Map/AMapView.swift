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
        let routeTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.routeTapped(_:)))
        routeTap.cancelsTouchesInView = false
        routeTap.delaysTouchesEnded = false
        routeTap.delegate = context.coordinator
        map.addGestureRecognizer(routeTap)
        context.coordinator.map = map
        return map
    }
    func updateUIView(_ map: MAMapView, context: Context) { context.coordinator.update(map) }
    static func dismantleUIView(_ map: MAMapView, coordinator: Coordinator) {
        coordinator.stopSelectionAnimation()
        coordinator.cancelRouteUpdates()
        coordinator.cancelPendingMapTap()
        coordinator.cancelPOIRefresh()
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
    @MainActor final class Coordinator: NSObject, @preconcurrency MAMapViewDelegate, UIGestureRecognizerDelegate {
        let store: AppStore
        weak var map: MAMapView?
        var pins: [String: Pin] = [:]
        var searchPins: [String: SearchPin] = [:]
        private var draftPin: MAPointAnnotation?
        var lines: [String: (MAPolyline, MAPolyline)] = [:]
        var overlayStyle: [ObjectIdentifier: (UIColor, Bool)] = [:]
        var lastRoutes: [String: RouteOverlayGeometry] = [:]
        private let routeProcessing = RouteProcessing()
        private var coordinateTask: Task<Void, Never>?
        private var desiredRoutes: [RouteOverlayGeometry] = []
        private var routeRevision = UUID()
        var lastCamera: UUID?
        var lastLocate: UUID?
        private var pendingLocate = false
        private var lastFollowMode: LocationFollowMode = .idle
        var routesVisible = true
        var lastStyledCompact: Bool?
        var lastStyledSelection: String?
        var pinImages: [String: UIImage] = [:]
        private var routeHitIndexes: [String: RouteSpatialIndex] = [:]
        private var motionProjection: [Coordinate: CGPoint] = [:]
        private var poiRefreshTask: Task<Void, Never>?
        private var poiCoverage: RouteGeoBounds?
        private var mapIsMoving = false
        private var highlightedRouteIDs: Set<String> = []
        private var selectionDay: String?
        private var selectionRequest: UUID?
        private var selectionLink: CADisplayLink?
        private var selectionRoutes: [DisplayRoute] = []
        private let motion = RouteMotionAnimation()
        private var motionDots: [CAShapeLayer] = []
        private var pendingRouteTap: DispatchWorkItem?
        private var mapTapAnnotation: MAAnnotation?
        private var mapTapPoint: CGPoint?
        private var mapTapClaimed = false
        private var filteringSearchPOIs = false
        private var renderedCoordinates: [String: [Coordinate]] = [:]
        init(_ store: AppStore) { self.store = store }
        func update(_ map: MAMapView) {
            updateRouteSelection(map)
            if let draft = store.draft, draft.marker == nil, !store.placeSearchPresented {
                let point = Coordinates.gcj(draft.coordinates)
                let pin = draftPin ?? MAPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                pin.title = draft.title
                if draftPin == nil { draftPin = pin; map.addAnnotation(pin) }
                if let view = map.view(for: pin) { styleDraftPin(view) }
            } else if let pin = draftPin {
                draftPin = nil
                MapInteractionFeedback.disappear(map.view(for: pin)) { [weak map] in map?.removeAnnotation(pin) }
            }
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
            updateSearchPOIFilter(map)
            updateRoutes(map)
            updateRouteSelection(map)
            if let command = store.camera, lastCamera != command.id {
                lastCamera = command.id
                let coords = command.points.map { p -> CLLocationCoordinate2D in
                    let gcj = Coordinates.gcj(p); return CLLocationCoordinate2D(latitude: gcj.latitude, longitude: gcj.longitude)
                }
                if coords.count == 1 {
                    let insets = padding(map, command: command)
                    let status = map.getMapStatus()!
                    status.centerCoordinate = coords[0]
                    status.zoomLevel = command.revealDraft ? map.zoomLevel : CGFloat(command.zoomLevel ?? 15)
                    if command.revealDraft {
                        let position = map.convert(coords[0], toPointTo: map)
                        let target = MapInteractionFeedback.revealTarget(position, bounds: map.bounds, insets: insets)
                        status.screenAnchor = CGPoint(x: target.x / max(1, map.bounds.width),
                                                      y: target.y / max(1, map.bounds.height))
                    }
                    if !command.revealDraft {
                        status.screenAnchor = CGPoint(
                            x: (map.bounds.width + insets.left - insets.right) / (2 * max(1, map.bounds.width)),
                            y: (map.bounds.height + insets.top - insets.bottom) / (2 * max(1, map.bounds.height)))
                    }
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
            updateSearchBounds(map)
            if lastFollowMode != store.locationMode {
                lastFollowMode = store.locationMode
                if store.locationMode == .idle { map.setUserTrackingMode(.none, animated: false) }
            }
            if lastLocate == nil { lastLocate = store.locating }
            else if lastLocate != store.locating {
                lastLocate = store.locating; map.showsUserLocation = true
                pendingLocate = true
                if let location = map.userLocation.location, location.horizontalAccuracy >= 0,
                   abs(location.timestamp.timeIntervalSinceNow) < 30 {
                    focusUserLocation(map, location: location)
                }
            }
        }
        func mapView(_ mapView: MAMapView!, didUpdate userLocation: MAUserLocation!, updatingLocation: Bool) {
            guard pendingLocate, updatingLocation, let mapView, let location = userLocation?.location,
                  location.horizontalAccuracy >= 0 else { return }
            focusUserLocation(mapView, location: location)
        }
        private func focusUserLocation(_ map: MAMapView, location: CLLocation) {
            guard pendingLocate, let status = map.getMapStatus() else { return }
            pendingLocate = false
            map.setUserTrackingMode(.none, animated: false)
            let insets = padding(map)
            status.centerCoordinate = location.coordinate
            status.zoomLevel = 15
            if store.locationMode != .heading { status.rotationDegree = 0 }
            status.screenAnchor = CGPoint(
                x: (map.bounds.width + insets.left - insets.right) / (2 * max(1, map.bounds.width)),
                y: (map.bounds.height + insets.top - insets.bottom) / (2 * max(1, map.bounds.height)))
            let duration = CameraMotion.duration(
                from: Coordinates.wgs(Coordinate(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)),
                to: Coordinates.wgs(Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)),
                currentZoom: Double(map.zoomLevel), targetZoom: 15,
                reduceMotion: UIAccessibility.isReduceMotionEnabled)
            withCameraAnimation(duration: duration) {
                map.setMapStatus(status, animated: duration > 0, duration: duration)
            }
            if store.locationMode == .heading { map.setUserTrackingMode(.followWithHeading, animated: duration > 0) }
        }
        private func padding(_ map: MAMapView, command: CameraCommand? = nil) -> UIEdgeInsets {
            let insets = (command ?? CameraCommand(points: [])).viewportInsets(base: store.mapViewportInsets,
                height: map.bounds.height, bottomSafeArea: map.safeAreaInsets.bottom,
                bottomSheet: UIDevice.current.userInterfaceIdiom != .pad)
            return UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
        func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
            if let pin = draftPin, annotation === pin {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "draft-location")
                    ?? MAAnnotationView(annotation: pin, reuseIdentifier: "draft-location")!
                view.annotation = pin
                view.canShowCallout = false
                view.image = nil
                styleDraftPin(view)
                return view
            }
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
        func stopSelectionAnimation() {
            selectionLink?.invalidate(); selectionLink = nil
            motionDots.forEach { $0.removeFromSuperlayer() }
            motionDots = []; motion.reset(); motionProjection.removeAll(keepingCapacity: true)
        }

        private func updateRouteSelection(_ map: MAMapView, geometryChanged: Bool = false) {
            let day = store.dayID
            let changed = day != selectionDay
            let resumeMotion = routesVisible && selectionLink == nil && !selectionRoutes.isEmpty && !UIAccessibility.isReduceMotionEnabled
            guard changed || geometryChanged || resumeMotion || selectionRequest != store.routeSelectionRequest else { return }
            selectionRequest = store.routeSelectionRequest
            // Repeated taps still reopen the day panel, but need no renderer/animation reset.
            guard changed || geometryChanged || resumeMotion else { return }
            let selected = store.displayRoutes.filter { $0.dayID == day && lastRoutes[$0.id]?.points == $0.points }
            let newGeometry = selected.map(RouteOverlayGeometry.init) != selectionRoutes.map(RouteOverlayGeometry.init)
            selectionDay = day; selectionRequest = store.routeSelectionRequest
            highlightRoutes(Set(selected.map(\.id)), map: map)
            guard changed || newGeometry || resumeMotion else { return }
            stopSelectionAnimation(); selectionRoutes = selected
            guard routesVisible, !selected.isEmpty, !UIAccessibility.isReduceMotionEnabled else { return }
            let converted = selected.map { route -> DisplayRoute in
                var value = route; value.points = renderedCoordinates[route.id] ?? []
                return value
            }
            let paths = RouteSelection.paths(converted)
            motion.reset(paths: paths)
            for _ in paths {
                let dot = CAShapeLayer()
                dot.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
                dot.path = UIBezierPath(ovalIn: dot.bounds.insetBy(dx: 1, dy: 1)).cgPath
                dot.fillColor = UIColor(Theme.color(selected.first?.colorIndex ?? 0)).cgColor
                dot.strokeColor = UIColor.white.cgColor; dot.lineWidth = 2
                dot.shadowColor = UIColor.black.cgColor; dot.shadowOpacity = 0.18; dot.shadowRadius = 2
                dot.zPosition = 1000; dot.isHidden = true
                map.layer.addSublayer(dot); motionDots.append(dot)
            }
            let link = CADisplayLink(target: self, selector: #selector(advanceSelection(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: Float(map.window?.screen.maximumFramesPerSecond ?? 60),
                                                         preferred: Float(map.window?.screen.maximumFramesPerSecond ?? 60))
            selectionLink = link; link.add(to: .main, forMode: .common)
        }

        private func highlightRoutes(_ selected: Set<String>, map: MAMapView) {
            let changed = highlightedRouteIDs.symmetricDifference(selected)
            highlightedRouteIDs = selected
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for id in changed {
                guard let pair = lines[id] else { continue }
                let active = selected.contains(id)
                if let white = map.renderer(for: pair.0) as? MAPolylineRenderer {
                    white.lineWidth = active ? 9 : 6; white.setNeedsUpdate()
                }
                if let color = map.renderer(for: pair.1) as? MAPolylineRenderer {
                    color.lineWidth = active ? 6 : 3.5; color.setNeedsUpdate()
                }
            }
            CATransaction.commit()
        }

        @objc private func advanceSelection(_ link: CADisplayLink) {
            guard let map, routesVisible, !UIAccessibility.isReduceMotionEnabled else { stopSelectionAnimation(); return }
            // A moving camera invalidates only this small endpoint cache, not all route points.
            if mapIsMoving || motionProjection.count > 256 { motionProjection.removeAll(keepingCapacity: true) }
            let positions = motion.positions(timestamp: link.targetTimestamp) { coordinate in
                if let point = self.motionProjection[coordinate] { return point }
                let point = map.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), toPointTo: map)
                self.motionProjection[coordinate] = point
                return point
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (position, dot) in zip(positions, motionDots) {
                guard let position else { dot.isHidden = true; continue }
                dot.position = position; dot.isHidden = false
            }
            CATransaction.commit()
        }

        private func withCameraAnimation(duration: TimeInterval, changes: () -> Void) {
            CATransaction.begin()
            // The SDK owns interpolation. Don't wrap it in a second layer animation.
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
        }

        func cancelRouteUpdates() {
            routeRevision = UUID(); coordinateTask?.cancel(); coordinateTask = nil
        }
        func cancelPOIRefresh() {
            poiRefreshTask?.cancel(); poiRefreshTask = nil
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
                        self.renderedCoordinates.removeValue(forKey: id)
                        self.routeHitIndexes.removeValue(forKey: id)
                    }
                    if !removed.isEmpty { map.removeOverlays(removed) }
                    var added: [MAPolyline] = []
                    for route in prepared { added += self.applyRoute(route, map: map) }
                    if self.routesVisible && !added.isEmpty { map.addOverlays(added) }
                }
                CATransaction.commit()
                self.coordinateTask = nil
                self.updateRouteSelection(map, geometryChanged: true)
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
            renderedCoordinates[route.id] = prepared.coordinates
            routeHitIndexes[route.id] = prepared.hitIndex
            return added
        }
        private func applyAnnotationOrder(_ view: MAAnnotationView, selected: Bool, search: Bool) {
            let order = selected ? (search ? 200_000 : 100_000) : search ? 1_000 : 100
            // SDK zIndex applies during annotation creation; the UIView layer also handles live selection.
            view.zIndex = order
            view.layer.zPosition = CGFloat(order)
            if selected { view.superview?.bringSubviewToFront(view) }
        }
        private var searchPOIsActive: Bool {
            store.placeSearchPresented || store.searching || !store.searchResults.isEmpty
        }
        private func updateSearchPOIFilter(_ map: MAMapView) {
            guard searchPOIsActive else {
                cancelPOIRefresh(); poiCoverage = nil
                if filteringSearchPOIs { map.removePoiFilter("search-results"); filteringSearchPOIs = false }
                return
            }
            // Normal SwiftUI updates don't mutate the SDK filter. Existing overscan
            // covers local movement; refresh its geometry once the map has settled.
            if !filteringSearchPOIs { refreshSearchPOIFilter(map) }
        }
        private func schedulePOIRefresh() {
            cancelPOIRefresh()
            guard searchPOIsActive else { return }
            poiRefreshTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard let self, !Task.isCancelled, !self.mapIsMoving,
                      self.searchPOIsActive, let map = self.map else { return }
                self.refreshSearchPOIFilter(map)
                self.poiRefreshTask = nil
            }
        }
        private func refreshSearchPOIFilter(_ map: MAMapView) {
            let rect = map.bounds
            guard rect.width > 0, rect.height > 0 else { return }
            let coordinates = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map {
                let c = map.convert($0, toCoordinateFrom: map)
                return Coordinate(latitude: c.latitude, longitude: c.longitude)
            }
            guard coordinates.allSatisfy(\.isValid) else { return }
            let reference = poiCoverage.map { ($0.west + $0.east) / 2 } ?? coordinates[0].longitude
            let viewport = RouteGeoBounds(points: coordinates, referenceLongitude: reference)
            guard poiCoverage?.contains(viewport) != true else { return }
            let coverage = viewport.expanded(factor: 1)
            let filter = MAPoiFilter()
            filter.filterType = .poi; filter.keyName = "search-results"
            filter.position = coverage.corners.map {
                NSValue(maCoordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            if filteringSearchPOIs { map.removePoiFilter("search-results") }
            map.add(filter); filteringSearchPOIs = true; poiCoverage = coverage
        }
        private func styleSearch(_ view: MAAnnotationView, pin: SearchPin) {
            let selected = store.selectedSearchPlaceID == pin.place.id
            let key = "search-\(selected)"
            if pinImages[key] == nil { pinImages[key] = SearchPinAppearance.image(selected: selected) }
            view.image = pinImages[key]; view.centerOffset = CGPoint(x: 0, y: -14)
            applyAnnotationOrder(view, selected: selected, search: true)
            view.isAccessibilityElement = true; view.accessibilityLabel = "搜索结果\(pin.number)：\(pin.place.name)"
            view.accessibilityIdentifier = "map-search-result-\(pin.place.id)"
        }
        private func styleDraftPin(_ view: MAAnnotationView) {
            let image = MapMarkerAppearance.draftImage(icon: store.draft?.icon ?? .location)
            let firstAppearance = view.image == nil
            view.image = image
            if firstAppearance { MapInteractionFeedback.appear(view) }
            // The tip (22, 42) is the selected geographic point.
            view.centerOffset = CGPoint(x: 0, y: -18)
            view.zIndex = 1000
        }
        private func markerImage(_ pin: Pin, dot: Bool, selected: Bool) -> UIImage {
            MapMarkerAppearance.image(icon: pin.marker.icon, compact: dot, selected: selected)
        }
        private func style(_ view: MAAnnotationView, pin: Pin, map: MAMapView) {
            let compact = MapZoomPresentation.isCompact(Double(map.zoomLevel))
            let selected = store.selectedMarker?.id == pin.markerID
            let image = markerImage(pin, dot: false, selected: selected)
            if view.image !== image { view.image = image }
            view.centerOffset = .zero
            applyAnnotationOrder(view, selected: selected, search: false)
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
            if !visible { stopSelectionAnimation() }
            let overlays = lines.values.flatMap { [$0.0, $0.1] }
            if visible {
                map.addOverlays(overlays)
                selectionRequest = nil; updateRouteSelection(map)
            } else { map.removeOverlays(overlays) }
        }
        func mapView(_ mapView: MAMapView!, regionWillChangeAnimated animated: Bool) {
            if mapView.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
                store.noteMapInteraction()
            }
            mapIsMoving = true; cancelPOIRefresh()
            motionProjection.removeAll(keepingCapacity: true)
        }
        func mapViewRegionChanged(_ mapView: MAMapView!) {
            motionProjection.removeAll(keepingCapacity: true)
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
            renderer.strokeColor = style.0
            let id = lines.first { $0.value.0 === line || $0.value.1 === line }?.key
            let selected = id.flatMap { key in store.displayRoutes.first { $0.id == key } }?.dayID == store.dayID && store.dayID != nil
            renderer.lineWidth = style.1 ? (selected ? 9 : 6) : (selected ? 6 : 3.5)
            return renderer
        }
        func mapView(_ mapView: MAMapView!, didSelect view: MAAnnotationView!) {
            if let pin = view.annotation as? SearchPin {
                mapTapAnnotation = pin; mapTapClaimed = true; cancelPendingMapTap()
                store.choose(pin.place, fromMap: true); mapView.deselectAnnotation(pin, animated: false)
            } else if let pin = view.annotation as? Pin {
                mapTapAnnotation = pin; mapTapClaimed = true; cancelPendingMapTap()
                store.focus(pin.marker); mapView.deselectAnnotation(pin, animated: false)
            }
        }
        func cancelPendingMapTap() {
            pendingRouteTap?.cancel()
            pendingRouteTap = nil
        }
        private func annotationAt(_ tap: CGPoint, map: MAMapView) -> MAAnnotationView? {
            (Array(pins.values).compactMap { map.view(for: $0) }
                + Array(searchPins.values).compactMap { map.view(for: $0) })
                .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.insetBy(
                    dx: min(0, ($0.bounds.width - 44) / 2),
                    dy: min(0, ($0.bounds.height - 44) / 2)).contains($0.convert(tap, from: map)) }
                .sorted {
                    let leftSaved = $0.annotation is Pin
                    let rightSaved = $1.annotation is Pin
                    return leftSaved != rightSaved ? leftSaved : $0.zIndex > $1.zIndex
                }.first
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer, let map {
                store.noteMapInteraction()
                cancelPendingMapTap()
                mapTapPoint = touch.location(in: map)
                mapTapAnnotation = annotationAt(mapTapPoint!, map: map)?.annotation
                mapTapClaimed = false
            }
            return true
        }
        func mapView(_ mapView: MAMapView!, didTouchPois pois: [Any]!) {
            guard !mapTapClaimed, mapTapAnnotation == nil,
                  !store.placeSearchPresented, store.draft?.marker == nil,
                  let poi = (pois ?? []).compactMap({ $0 as? MATouchPoi }).first else { return }
            if let tap = mapTapPoint, annotationAt(tap, map: mapView) != nil { return }
            mapTapClaimed = true
            cancelPendingMapTap()
            let coordinate = Coordinates.wgs(Coordinate(latitude: poi.coordinate.latitude,
                                                        longitude: poi.coordinate.longitude))
            store.create(at: coordinate, poiName: poi.name)
        }
        func mapView(_ mapView: MAMapView!, didLongPressedAt coordinate: CLLocationCoordinate2D) {
            cancelPendingMapTap()
            store.create(at: Coordinates.wgs(Coordinate(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude)))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func routeTapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = map else { return }
            let tap = gesture.location(in: mapView)
            // Use the visible annotation views: no SDK coordinate projection or delayed
            // didSelect callback is needed to acknowledge a marker tap.
            cancelPendingMapTap()
            let annotation = mapTapAnnotation ?? annotationAt(tap, map: mapView)?.annotation
            if let annotation {
                mapTapAnnotation = annotation
                mapTapClaimed = true
                if let pin = annotation as? SearchPin {
                    store.choose(pin.place, fromMap: true)
                    if let view = mapView.view(for: pin) { styleSearch(view, pin: pin) }
                } else if let pin = annotation as? Pin {
                    store.focus(pin.marker); updatePinStyles(mapView)
                }
                return
            }
            guard !mapTapClaimed else { return }
            // Route navigation is decided by the SDK's map tap callback, not this gesture.
        }
        func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
            guard !mapTapClaimed, mapTapAnnotation == nil, store.draft == nil else { return }
            let tap = mapTapPoint ?? mapView.convert(coordinate, toPointTo: mapView)
            cancelPendingMapTap()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView, !self.mapTapClaimed, self.store.draft == nil else { return }
                self.selectRoute(at: tap, mapView: mapView)
            }
            pendingRouteTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        private func selectRoute(at tap: CGPoint, mapView: MAMapView) {
            guard !store.placeSearchPresented, !MapZoomPresentation.isCompact(Double(mapView.zoomLevel)) else { return }
            let radius = RouteSelection.hitRadius
            let ground = [CGPoint(x: tap.x-radius, y: tap.y-radius), CGPoint(x: tap.x+radius, y: tap.y-radius),
                          CGPoint(x: tap.x+radius, y: tap.y+radius), CGPoint(x: tap.x-radius, y: tap.y+radius)].map {
                let c = mapView.convert($0, toCoordinateFrom: mapView)
                return Coordinate(latitude: c.latitude, longitude: c.longitude)
            }
            guard ground.allSatisfy(\.isValid) else { return }
            let bounds = RouteGeoBounds(points: ground, referenceLongitude: ground[0].longitude)
            var projected: [Coordinate: CGPoint] = [:]
            let hits = store.displayRoutes.compactMap { route -> (DisplayRoute, Double)? in
                guard let index = routeHitIndexes[route.id] else { return nil }
                let distance = index.nearestDistance(at: tap, bounds: bounds) { coordinate in
                    if let cached = projected[coordinate] { return cached }
                    let point = mapView.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), toPointTo: mapView)
                    projected[coordinate] = point; return point
                }
                return distance <= radius ? (route, distance) : nil
            }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }
            let nearest = hits.first?.1 ?? .infinity
            var days: Set<String> = []
            let unique = hits.filter { $0.1 <= nearest + 2 }.compactMap {
                days.insert($0.0.tripID + "|" + $0.0.dayID).inserted ? $0.0 : nil
            }
            if unique.count > 1 { store.offerRoutes(unique, at: tap) }
            else if let first = unique.first {
                // Feedback is committed in the gesture callback, before navigation publishes.
                highlightRoutes(Set(store.displayRoutes.filter { $0.tripID == first.tripID && $0.dayID == first.dayID }.map(\.id)), map: mapView)
                store.selectRoute(first)
            }
            else { store.routeCandidates = [] }
        }
        func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool) {
            updateZoomPresentation(mapView)
            updateSearchBounds(mapView)
            mapIsMoving = false
            motionProjection.removeAll(keepingCapacity: true)
            schedulePOIRefresh()
        }
        private func updateSearchBounds(_ mapView: MAMapView) {
            let insets = padding(mapView)
            let rect = mapView.bounds.inset(by: insets)
            guard rect.width > 0, rect.height > 0 else { return }
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
    @State private var motionActive = false
    @State private var motion = RouteMotionAnimation()
    private var zoom: Double { previewZoom + log2(max(0.01, magnification)) }
    func point(_ p: Coordinate, size: CGSize) -> CGPoint {
        let insets = store.mapViewportInsets
        let usableWidth = max(80, size.width - insets.left - insets.right)
        let usableHeight = max(80, size.height - insets.top - insets.bottom)
        if let command = store.camera, command.detailLayout != nil, let center = command.points.first {
            let target = command.viewportInsets(base: insets, height: size.height, bottomSafeArea: 0,
                bottomSheet: UIDevice.current.userInterfaceIdiom != .pad)
            return CGPoint(x: (size.width + target.left - target.right) / 2 + (p.longitude - center.longitude) * usableWidth / 0.018,
                           y: (size.height + target.top - target.bottom) / 2 - (p.latitude - center.latitude) * usableHeight / 0.029)
        }
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
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: store.dayID == route.dayID ? 9 : 6, lineCap: .round))
                        context.stroke(path, with: .color(Theme.color(route.colorIndex)), style: StrokeStyle(lineWidth: store.dayID == route.dayID ? 6 : 3.5, lineCap: .round))
                    }
                }
                TimelineView(.animation(paused: !motionActive)) { timeline in
                    Canvas { context, size in
                        guard motionActive, !MapZoomPresentation.isCompact(zoom) else { return }
                        let routes = store.displayRoutes.filter { $0.dayID == store.dayID }
                        let positions = motion.positions(timestamp: timeline.date.timeIntervalSinceReferenceDate) {
                            point($0, size: size)
                        }
                        for position in positions {
                            guard let p = position else { continue }
                            let circle = Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                            context.fill(circle, with: .color(Theme.color(routes.first?.colorIndex ?? 0)))
                            context.stroke(circle, with: .color(.white), lineWidth: 2)
                        }
                    }
                }.allowsHitTesting(false)
                ForEach(store.mapMarkers) { marker in
                    Button { store.focus(marker) } label: {
                        MapMarkerCircle(icon: marker.icon, selected: store.selectedMarker?.id == marker.id,
                                        compact: MapZoomPresentation.isCompact(zoom))
                            .animation(reduceMotion ? nil : .easeOut(duration: MapZoomPresentation.transitionDuration), value: MapZoomPresentation.isCompact(zoom))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel(marker.title).accessibilityIdentifier("map-marker-\(marker.id)")
                        .accessibilityValue(MapZoomPresentation.isCompact(zoom) ? "圆点" : "图标")
                        .position(point(marker.coordinates, size: proxy.size))
                        .zIndex(store.selectedMarker?.id == marker.id ? 100_000 : 100)
                }
                ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, place in
                    Button { store.choose(place, fromMap: true) } label: {
                        Image(uiImage: SearchPinAppearance.image(selected: store.selectedSearchPlaceID == place.id))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("搜索结果\(index + 1)：\(place.name)")
                        .accessibilityIdentifier("map-search-result-\(place.id)")
                        .offset(y: -14)
                        .position(point(place.coordinates, size: proxy.size))
                        .zIndex(store.selectedSearchPlaceID == place.id ? 200_000 : 1_000)
                }
                Text("模拟器 · 交互预览画布").font(.caption2).foregroundStyle(.secondary)
                    .padding(6).background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.bottom, store.mapViewportInsets.bottom+12).padding(.leading, store.mapViewportInsets.left+8)
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("preview-map-surface")
            .task(id: "\(store.dayID ?? "")|\(store.routeSelectionRequest)|\(store.displayRoutes.count)") {
                guard store.dayID != nil, !reduceMotion else { motionActive = false; return }
                motion.reset(paths: RouteSelection.paths(store.displayRoutes.filter { $0.dayID == store.dayID }))
                motionActive = true
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                guard !store.placeSearchPresented, !MapZoomPresentation.isCompact(zoom) else { return }
                if store.mapMarkers.contains(where: { marker in
                    let p = point(marker.coordinates, size: proxy.size)
                    return hypot(p.x - value.location.x, p.y - value.location.y) <= 22
                }) { return }
                let candidates = RouteSelection.candidates(at: (value.location.x, value.location.y), routes: store.displayRoutes) {
                    let p = point($0, size: proxy.size); return (p.x, p.y)
                }
                if candidates.count > 1 { store.offerRoutes(candidates, at: value.location) }
                else if let route = candidates.first { store.selectRoute(route) }
                else { store.routeCandidates = [] }
            })
            .onLongPressGesture {
                store.create(at: Coordinate(latitude: 31.219, longitude: 121.443))
            }
            .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in
                state = value.magnification
            }.onEnded { value in
                previewZoom = min(20, max(3, previewZoom + log2(max(0.01, value.magnification))))
            })
        }
    }
}
