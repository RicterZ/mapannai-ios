import SwiftUI
import MapKit

@MainActor struct AppleMapRendererFactory: MapRendererFactory {
    let kind: MapRendererKind = .apple
    func makeMap(store: AppStore, settings: Settings, onOpenSettings: @escaping () -> Void) -> AnyView {
        AnyView(AppleMapRenderer(store: store))
    }
}

struct AppleMapRenderer: UIViewRepresentable {
    @ObservedObject var store: AppStore
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false; map.showsScale = true; map.showsUserLocation = true
        map.selectableMapFeatures = [.pointsOfInterest]
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), latitudinalMeters: 8000, longitudinalMeters: 8000), animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator; map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.5; map.addGestureRecognizer(press)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { coordinator.tapArbiter.cancel(); coordinator.userDirection.stop(); map.delegate = nil; map.showsUserLocation = false }

    final class Pin: MKPointAnnotation {
        let key: String
        var marker: Marker?
        var place: Place?
        init(key: String, coordinate: Coordinate, title: String) {
            self.key = key; super.init(); self.coordinate = Self.coordinate(coordinate); self.title = title
        }
        static func coordinate(_ point: Coordinate) -> CLLocationCoordinate2D {
            let displayed = Coordinates.gcj(point)
            return CLLocationCoordinate2D(latitude: displayed.latitude, longitude: displayed.longitude)
        }
    }
    final class Line: MKPolyline { var colorIndex = 0; var dayID = ""; var overview = false; var casing = false; var isDashed = false }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let store: AppStore
        let tapArbiter = MapTapArbiter()
        let userDirection = UserDirectionIndicator()
        let navigationGestures = MapNavigationGestures()
        var lastTap: CGPoint?
        var selectedPOI: MKMapFeatureAnnotation?
        var selectedPOIDraftID: UUID?
        var pins: [String: Pin] = [:]
        var routes: [DisplayRoute] = []
        var lastCamera: UUID?
        var lastLocate: UUID?
        var pendingLocate = false
        var lastFollowMode: LocationFollowMode = .idle
        var compact = false
        var dashScale = 0.0
        var dashCoverage = MKMapRect.null
        init(_ store: AppStore) { self.store = store }
        func update(_ map: MKMapView) {
            navigationGestures.onTransformEnded = { [weak self, weak map] in
                guard let self, let map, self.store.locationMode != .idle else { return }
                let desired: MKUserTrackingMode = self.store.locationMode == .heading ? .followWithHeading : .follow
                if map.userTrackingMode != desired {
                    map.setUserTrackingMode(desired, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            }
            navigationGestures.observe(map) { [weak self] in self?.store.noteMapInteraction() }
            let insets = store.mapViewportInsets
            map.insetsLayoutMarginsFromSafeArea = false
            map.layoutMargins = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            compact = isCompact(map)
            userDirection.attach(to: map, project: { [weak map] in
                guard let map, map.userLocation.location != nil else { return nil }
                return map.convert(map.userLocation.coordinate, toPointTo: map)
            }, bearing: { [weak map] in map?.camera.heading ?? 0 })
            // MapKit owns heading tracking, camera animation and pinch interaction.
            userDirection.onHeading = nil
            var desired: [String: (Coordinate, String, Marker?, Place?)] = [:]
            for marker in store.mapMarkers { desired["saved/" + marker.id] = (marker.coordinates, marker.title, marker, nil) }
            for place in store.searchResults { desired["search/" + place.id] = (place.coordinates, place.name, nil, place) }
            if let feature = selectedPOI, store.draft?.id != selectedPOIDraftID {
                selectedPOI = nil; selectedPOIDraftID = nil
                map.deselectAnnotation(feature, animated: true)
            }
            if let draft = store.draft, selectedPOI == nil { desired["draft"] = (draft.coordinates, draft.title, nil, nil) }
            for key in Array(pins.keys) where desired[key] == nil {
                let pin = pins.removeValue(forKey: key)!
                if key == "draft" { MapInteractionFeedback.disappear(map.view(for: pin)) { [weak map] in map?.removeAnnotation(pin) } }
                else { map.removeAnnotation(pin) }
            }
            for (key, value) in desired {
                let pin = pins[key] ?? Pin(key: key, coordinate: value.0, title: value.1)
                pin.marker = value.2; pin.place = value.3
                pin.coordinate = Pin.coordinate(value.0); pin.title = value.1
                if pins[key] == nil { pins[key] = pin; map.addAnnotation(pin) }
                if let view = map.view(for: pin) { style(view, pin: pin) }
            }
            map.pointOfInterestFilter = store.placeSearchPresented ? .excludingAll : .includingAll
            map.selectableMapFeatures = store.placeSearchPresented ? [] : [.pointsOfInterest]
            if routes.map(RouteOverlayGeometry.init) != store.displayRoutes.map(RouteOverlayGeometry.init) {
                routes = store.displayRoutes
                map.removeOverlays(map.overlays.filter { $0 is Line })
                dashScale = 0
                for route in routes {
                    var coordinates = MapZoomPresentation.endpoints(route).map(Pin.coordinate)
                    let line = Line(coordinates: &coordinates, count: coordinates.count)
                    line.colorIndex = route.colorIndex; line.dayID = route.dayID; line.overview = true
                    map.addOverlay(line, level: .aboveRoads)
                }
                for route in routes where !route.isDashed {
                    var coordinates = route.points.map(Pin.coordinate)
                    for casing in [true, false] {
                        let line = Line(coordinates: &coordinates, count: coordinates.count)
                        line.colorIndex = route.colorIndex; line.dayID = route.dayID; line.casing = casing; line.isDashed = route.isDashed
                        map.addOverlay(line)
                    }
                }
            }
            updateDashedRoutes(map)
            for overlay in map.overlays {
                if let line = overlay as? Line, let renderer = map.renderer(for: line) as? MKPolylineRenderer {
                    styleRoute(renderer, line: line)
                }
            }
            if let command = store.camera, command.id != lastCamera {
                lastCamera = command.id
                focus(map, command: command)
            }
            if lastFollowMode != store.locationMode {
                lastFollowMode = store.locationMode
                if store.locationMode == .idle { map.setUserTrackingMode(.none, animated: false) }
            }
            if lastLocate == nil { lastLocate = store.locating }
            else if lastLocate != store.locating {
                lastLocate = store.locating; pendingLocate = true; map.showsUserLocation = true
                if let location = map.userLocation.location, abs(location.timestamp.timeIntervalSinceNow) < 30 { locate(map, location: location) }
            }
        }
        func focus(_ map: MKMapView, command: CameraCommand) {
            guard !command.points.isEmpty else { return }
            let insets = command.viewportInsets(base: store.mapViewportInsets, height: map.bounds.height,
                bottomSafeArea: map.safeAreaInsets.bottom, bottomSheet: UIDevice.current.userInterfaceIdiom != .pad)
            let padding = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            if command.revealDraft, let point = command.points.first {
                let screen = map.convert(Pin.coordinate(point), toPointTo: map)
                let target = MapInteractionFeedback.revealTarget(screen, bounds: map.bounds, insets: padding)
                let center = CGPoint(x: map.bounds.midX + screen.x - target.x, y: map.bounds.midY + screen.y - target.y)
                map.setCenter(map.convert(center, toCoordinateFrom: map), animated: !UIAccessibility.isReduceMotionEnabled)
                return
            }
            var rect = MKMapRect.null
            for point in command.points { let p = MKMapPoint(Pin.coordinate(point)); rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) }
            if command.points.count == 1 {
                let point = MKMapPoint(Pin.coordinate(command.points[0]))
                let zoom = command.revealDraft ? log2(MKMapSize.world.width * max(map.bounds.width, 1) / max(map.visibleMapRect.width, 1) / 256) : command.singlePointZoom
                let width = MKMapSize.world.width * max(1, map.bounds.width - padding.left - padding.right) / (256 * pow(2, zoom))
                let height = width * max(1, map.bounds.height - padding.top - padding.bottom) / max(1, map.bounds.width - padding.left - padding.right)
                rect = MKMapRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            }
            map.setVisibleMapRect(rect, edgePadding: padding, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        static func internalCoordinate(_ coordinate: CLLocationCoordinate2D) -> Coordinate {
            Coordinates.wgs(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func locate(_ map: MKMapView, location: CLLocation) {
            guard pendingLocate, location.horizontalAccuracy >= 0 else { return }
            pendingLocate = false
            centerUser(map, location: location, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        private func centerUser(_ map: MKMapView, location: CLLocation, animated: Bool) {
            map.setUserTrackingMode(store.locationMode == .heading ? .followWithHeading : .follow, animated: animated)
            userDirection.refresh()
        }
        func isCompact(_ map: MKMapView) -> Bool {
            // Derive scale from a fixed-distance camera, never from the rotated viewport box.
            let camera = map.camera
            let metersPerPoint = max(camera.centerCoordinateDistance, 1) * 0.8284271247461901 / max(map.bounds.height, 1)
            let worldMeters = 40075016.68557849 * max(cos(camera.centerCoordinate.latitude * .pi / 180), 0.01)
            let zoom = log2(worldMeters / (256 * metersPerPoint))
            return MapZoomPresentation.isCompact(zoom)
        }
        func updateDashedRoutes(_ map: MKMapView) {
            let dashed = routes.filter(\.isDashed)
            guard !dashed.isEmpty, map.bounds.width > 0, map.bounds.height > 0 else { return }
            // Ground scale from camera distance, independent of the rotated viewport box.
            let metersPerPoint = max(map.camera.centerCoordinateDistance,1) * 0.8284271247461901 / map.bounds.height
            let scale = metersPerPoint * MKMapPointsPerMeterAtLatitude(map.camera.centerCoordinate.latitude)
            let visible = map.visibleMapRect
            guard dashScale == 0 || abs(log2(scale/dashScale)) >= 0.125 || !dashCoverage.contains(visible) else { return }
            dashScale = scale
            dashCoverage = visible.insetBy(dx:-visible.size.width,dy:-visible.size.height)
            let clip = CGRect(x:dashCoverage.minX,y:dashCoverage.minY,width:dashCoverage.width,height:dashCoverage.height)
            var added: [Line] = []
            for route in dashed {
                let points = route.points.map { point -> CGPoint in
                    let p = MKMapPoint(Pin.coordinate(point)); return CGPoint(x:p.x,y:p.y)
                }
                for segment in RouteDashGeometry.segments(points,unitsPerPoint:scale,clip:clip) {
                    var coordinates = segment.map { MKMapPoint(x:$0.x,y:$0.y).coordinate }
                    for casing in [true, false] {
                        let line = Line(coordinates:&coordinates,count:coordinates.count)
                        line.colorIndex = route.colorIndex; line.dayID = route.dayID; line.isDashed = true
                        line.casing = casing
                        added.append(line)
                    }
                }
            }
            let old = map.overlays.compactMap { $0 as? Line }.filter(\.isDashed)
            // Only replace dash geometry at zoom steps; solid renderer owns stroke width.
            UIView.performWithoutAnimation { map.addOverlays(added); map.removeOverlays(old) }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            navigationGestures.observe(mapView) { [weak self] in self?.store.noteMapInteraction() }
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            userDirection.refresh()
            updateDashedRoutes(mapView)
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            compact = isCompact(mapView)
            for pin in pins.values { if let view = mapView.view(for: pin) { style(view, pin: pin) } }
            for overlay in mapView.overlays {
                if let line = overlay as? Line, let renderer = mapView.renderer(for: line) as? MKPolylineRenderer { styleRoute(renderer, line: line) }
            }

            let a = Self.internalCoordinate(mapView.convert(CGPoint(x: 0, y: 0), toCoordinateFrom: mapView))
            let b = Self.internalCoordinate(mapView.convert(CGPoint(x: mapView.bounds.width, y: mapView.bounds.height), toCoordinateFrom: mapView))
            store.bounds = SearchBounds(west: min(a.longitude, b.longitude), south: min(a.latitude, b.latitude), east: max(a.longitude, b.longitude), north: max(a.latitude, b.latitude))
        }
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) { if let location = userLocation.location { locate(mapView, location: location); userDirection.refresh() } }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place") ?? MKAnnotationView(annotation: pin, reuseIdentifier: "place")
            view.annotation = pin; view.canShowCallout = false; style(view, pin: pin); return view
        }
        func style(_ view: MKAnnotationView, pin: Pin) {
            let firstDraft = pin.key == "draft" && view.accessibilityIdentifier != "map-draft-pin"
            view.alpha = 1
            view.accessibilityIdentifier = pin.key == "draft" ? "map-draft-pin" : pin.key
            if let marker = pin.marker {
                view.image = MapMarkerAppearance.image(icon: marker.icon, compact: compact, selected: store.selectedMarker?.id == marker.id)
            } else if pin.key == "draft" {
                view.image = MapMarkerAppearance.draftImage(icon: store.draft?.icon ?? .location)
            } else {
                view.image = SearchPinAppearance.image(selected: store.selectedSearchPlaceID == pin.place?.id)
            }
            view.centerOffset = pin.key == "draft" ? CGPoint(x: 0, y: -18) : pin.marker == nil ? CGPoint(x: 0, y: -14) : .zero
            view.transform = .identity
            view.zPriority = store.selectedMarker?.id == pin.marker?.id && pin.marker != nil ? .max : pin.marker != nil ? .defaultSelected : .defaultUnselected
            if pin.key == "draft" { view.zPriority = .max }
            if firstDraft { MapInteractionFeedback.appear(view) }
            view.displayPriority = .required
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? Line else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.shouldRasterize = false
            styleRoute(renderer, line: line)
            return renderer
        }
        private func styleRoute(_ renderer: MKPolylineRenderer, line: Line) {
            let selected = line.dayID == store.dayID
            renderer.alpha = line.overview == compact ? 1 : 0
            renderer.strokeColor = line.casing ? RouteLineAppearance.outline(line.colorIndex) : RouteLineAppearance.color(line.colorIndex)
            renderer.lineWidth = line.overview ? 1 : line.casing ? RouteLineAppearance.outlineWidth(selected: selected, dashed: line.isDashed) : RouteLineAppearance.width(selected: selected, dashed: line.isDashed)
            renderer.lineCap = line.isDashed ? .butt : .round; renderer.lineJoin = .round
            // Dashed routes are native solid polylines; never use rasterized dash styling.
            renderer.lineDashPattern = nil
        }
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let pin = annotation as? Pin {
                tapArbiter.claim()
                if let marker = pin.marker { store.focus(marker) }
                else if let place = pin.place { store.choose(place, fromMap: true) }
            } else if let feature = annotation as? MKMapFeatureAnnotation, !store.placeSearchPresented {
                if let point = lastTap, let pin = hitPin(mapView, at: point), let marker = pin.marker {
                    tapArbiter.claim(); store.focus(marker)
                } else {
                    tapArbiter.claim()
                    selectedPOI = feature
                    store.create(at: Self.internalCoordinate(feature.coordinate), poiName: feature.title)
                    selectedPOIDraftID = store.draft?.id
                    store.resolveApplePOI(feature)
                    return // Keep the native POI selection; no duplicate custom pin.
                }
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            if let feature = selectedPOI { map.deselectAnnotation(feature, animated: true) }
            selectedPOI = nil; selectedPOIDraftID = nil
            store.noteMapInteraction(); store.create(at: Self.internalCoordinate(coordinate))
        }
        func hitPin(_ map: MKMapView, at point: CGPoint) -> Pin? {
            pins.values.sorted { ($0.marker != nil ? 1 : 0) > ($1.marker != nil ? 1 : 0) }.first { pin in
                guard let view = map.view(for: pin) else { return false }
                let local = view.convert(point, from: map)
                return view.bounds.insetBy(dx: min(0, (view.bounds.width - 44)/2), dy: min(0, (view.bounds.height - 44)/2)).contains(local)
            }
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            store.noteMapInteraction()
            let point = gesture.location(in: map)
            lastTap = point
            if let pin = hitPin(map, at: point) {
                tapArbiter.claim()
                if let marker = pin.marker { store.focus(marker) }
                else if let place = pin.place { store.choose(place, fromMap: true) }
                return
            }
            for annotation in map.annotations {
                if let view = map.view(for: annotation), view.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
            }
            guard !store.placeSearchPresented, !compact else { return }
            let candidates = RouteSelection.candidates(at: (point.x, point.y), routes: routes) { coordinate in
                let projected = map.convert(Pin.coordinate(coordinate), toPointTo: map); return (projected.x, projected.y)
            }
            tapArbiter.scheduleRoute { [weak self] in
                guard let self else { return }
                if candidates.count == 1, let route = candidates.first { self.store.selectRoute(route) }
                else if !candidates.isEmpty { self.store.offerRoutes(candidates, at: point) }
            }
        }
    }
}
