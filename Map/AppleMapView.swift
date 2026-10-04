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
    final class Line: MKPolyline { var colorIndex = 0; var dayID = ""; var casing = false }
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
                for route in routes {
                    var coordinates = route.points.map(Pin.coordinate)
                    for casing in [true, false] {
                        let line = Line(coordinates: &coordinates, count: coordinates.count)
                        line.colorIndex = route.colorIndex; line.dayID = route.dayID; line.casing = casing
                        map.addOverlay(line)
                    }
                }
            }
            for overlay in map.overlays {
                if let line = overlay as? Line, let renderer = map.renderer(for: line) as? MKPolylineRenderer {
                    let width = line.casing ? RouteLineAppearance.outlineWidth(selected: line.dayID == store.dayID) : RouteLineAppearance.width(selected: line.dayID == store.dayID)
                    if renderer.lineWidth != width { renderer.lineWidth = width }
                    (renderer as? AppleRouteRenderer)?.showsDirections = !line.casing && line.dayID == store.dayID && !store.placeSearchPresented
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
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            navigationGestures.observe(mapView) { [weak self] in self?.store.noteMapInteraction() }
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { userDirection.refresh() }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            compact = isCompact(mapView)
            for pin in pins.values { if let view = mapView.view(for: pin) { style(view, pin: pin) } }
            for overlay in mapView.overlays { mapView.renderer(for: overlay)?.alpha = compact ? 0 : 1 }

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
            let renderer = AppleRouteRenderer(polyline: line)
            renderer.showsDirections = !line.casing && line.dayID == store.dayID && !store.placeSearchPresented
            renderer.shouldRasterize = false
            renderer.alpha = compact ? 0 : 1; renderer.strokeColor = line.casing ? RouteLineAppearance.outline(line.colorIndex) : RouteLineAppearance.color(line.colorIndex); renderer.lineWidth = line.casing ? RouteLineAppearance.outlineWidth(selected: line.dayID == store.dayID) : RouteLineAppearance.width(selected: line.dayID == store.dayID)
            renderer.lineCap = .round; renderer.lineJoin = .round
            return renderer
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
