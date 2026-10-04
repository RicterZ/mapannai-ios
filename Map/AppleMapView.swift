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
        map.showsCompass = false; map.showsScale = true
        map.selectableMapFeatures = [.pointsOfInterest]
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), latitudinalMeters: 8000, longitudinalMeters: 8000), animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator; map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.5; map.addGestureRecognizer(press)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(map) }
    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) { map.delegate = nil; map.showsUserLocation = false }

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
    final class Line: MKPolyline { var colorIndex = 0 }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let store: AppStore
        var pins: [String: Pin] = [:]
        var routes: [DisplayRoute] = []
        var lastCamera: UUID?
        var lastLocate: UUID?
        var pendingLocate = false
        init(_ store: AppStore) { self.store = store }
        func update(_ map: MKMapView) {
            var desired: [String: (Coordinate, String, Marker?, Place?)] = [:]
            for marker in store.mapMarkers { desired["saved/" + marker.id] = (marker.coordinates, marker.title, marker, nil) }
            for place in store.searchResults { desired["search/" + place.id] = (place.coordinates, place.name, nil, place) }
            if let draft = store.draft { desired["draft"] = (draft.coordinates, draft.title, nil, nil) }
            for key in Array(pins.keys) where desired[key] == nil { map.removeAnnotation(pins.removeValue(forKey: key)!) }
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
                map.removeOverlays(map.overlays)
                for route in routes {
                    var coordinates = route.points.map(Pin.coordinate)
                    let line = Line(coordinates: &coordinates, count: coordinates.count)
                    line.colorIndex = route.colorIndex
                    map.addOverlay(line)
                }
            }
            if let command = store.camera, command.id != lastCamera {
                lastCamera = command.id
                focus(map, command: command)
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
            focus(map, command: CameraCommand(points: [Self.internalCoordinate(map.userLocation.coordinate)]))
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let a = Self.internalCoordinate(mapView.convert(CGPoint(x: 0, y: 0), toCoordinateFrom: mapView))
            let b = Self.internalCoordinate(mapView.convert(CGPoint(x: mapView.bounds.width, y: mapView.bounds.height), toCoordinateFrom: mapView))
            store.bounds = SearchBounds(west: min(a.longitude, b.longitude), south: min(a.latitude, b.latitude), east: max(a.longitude, b.longitude), north: max(a.latitude, b.latitude))
        }
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) { if let location = userLocation.location { locate(mapView, location: location) } }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place") ?? MKAnnotationView(annotation: pin, reuseIdentifier: "place")
            view.annotation = pin; view.canShowCallout = false; style(view, pin: pin); return view
        }
        func style(_ view: MKAnnotationView, pin: Pin) {
            view.image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
                let color = pin.marker.map { UIColor(red: CGFloat((($0.content.iconType ?? .landmark).colorRGB >> 16) & 255) / 255, green: CGFloat((($0.content.iconType ?? .landmark).colorRGB >> 8) & 255) / 255, blue: CGFloat(($0.content.iconType ?? .landmark).colorRGB & 255) / 255, alpha: 1) } ?? .systemBlue
                color.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 28, height: 28))
                UIColor.white.setStroke(); context.cgContext.setLineWidth(2); context.cgContext.strokeEllipse(in: CGRect(x: 2, y: 2, width: 28, height: 28))
                let symbol = pin.marker?.content.iconType?.emoji ?? (pin.key == "draft" ? "○" : "●")
                (symbol as NSString).draw(at: CGPoint(x: 7, y: 5), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.white])
            }
            view.transform = CGAffineTransform(scaleX: store.selectedMarker?.id == pin.marker?.id && pin.marker != nil ? 1.15 : 1, y: store.selectedMarker?.id == pin.marker?.id && pin.marker != nil ? 1.15 : 1)
            view.displayPriority = .required
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? Line else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = UIColor(Theme.color(line.colorIndex)); renderer.lineWidth = 4
            return renderer
        }
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let pin = annotation as? Pin {
                if let marker = pin.marker { store.focus(marker) }
                else if let place = pin.place { store.choose(place, fromMap: true) }
            } else if let feature = annotation as? MKMapFeatureAnnotation, !store.placeSearchPresented {
                store.create(at: Self.internalCoordinate(feature.coordinate), poiName: feature.title)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            store.noteMapInteraction(); store.create(at: Self.internalCoordinate(coordinate))
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            store.noteMapInteraction()
            let point = gesture.location(in: map)
            for annotation in map.annotations {
                if let view = map.view(for: annotation), view.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
            }
            guard !store.placeSearchPresented else { return }
            let candidates = RouteSelection.candidates(at: (point.x, point.y), routes: routes) { coordinate in
                let projected = map.convert(Pin.coordinate(coordinate), toPointTo: map); return (projected.x, projected.y)
            }
            if candidates.count == 1, let route = candidates.first { store.selectRoute(route) }
            else if !candidates.isEmpty { store.offerRoutes(candidates, at: point) }
        }
    }
}
