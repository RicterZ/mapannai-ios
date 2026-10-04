import SwiftUI
import GoogleMaps
import CoreLocation

@MainActor struct GoogleMapRendererFactory: MapRendererFactory {
    let kind: MapRendererKind = .google
    func makeMap(store: AppStore, settings: Settings, onOpenSettings: @escaping () -> Void) -> AnyView {
        guard GoogleMapBootstrap.configure() else { return AnyView(AppleMapRenderer(store: store)) }
        return AnyView(GoogleMapRenderer(store: store))
    }
}
@MainActor enum GoogleMapBootstrap {
    private static var initialized = false
    static func configure() -> Bool {
        guard !AppConfiguration.googleMapsKey.isEmpty else { return false }
        if !initialized { initialized = GMSServices.provideAPIKey(AppConfiguration.googleMapsKey) }
        return initialized
    }
}

struct GoogleMapRenderer: UIViewRepresentable {
    @ObservedObject var store: AppStore
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: 31.2304, longitude: 121.4737, zoom: 13)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator; map.isMyLocationEnabled = true
        map.settings.compassButton = false; map.settings.myLocationButton = false
        return map
    }
    func updateUIView(_ map: GMSMapView, context: Context) { context.coordinator.update(map) }
    static func dismantleUIView(_ map: GMSMapView, coordinator: Coordinator) {
        coordinator.tapArbiter.cancel(); coordinator.routeMotion.stop(); coordinator.userDirection.stop(); coordinator.stopHeading(); coordinator.locationObservation = nil; map.delegate = nil; map.isMyLocationEnabled = false
    }
    @MainActor final class Coordinator: NSObject, GMSMapViewDelegate, CLLocationManagerDelegate {
        let store: AppStore
        let tapArbiter = MapTapArbiter()
        let routeMotion = RouteMotionOverlay()
        var directionLines: [GMSPolyline] = []
        let userDirection = UserDirectionIndicator()
        var poiInfoMarker: GMSMarker?
        var poiDraftID: UUID?
        private let headingManager = CLLocationManager()
        var markers: [String: GMSMarker] = [:]
        var lines: [String: GMSPolyline] = [:]
        var casings: [String: GMSPolyline] = [:]
        var geometries: [RouteOverlayGeometry] = []
        var lastCamera: UUID?
        var lastLocate: UUID?
        var pendingLocate = false
        var searchStyleEnabled: Bool?
        weak var map: GMSMapView?
        var locationObservation: NSKeyValueObservation?
        init(_ store: AppStore) { self.store = store; super.init(); headingManager.delegate = self }
        static func coordinate(_ point: Coordinate) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        func update(_ map: GMSMapView) {
            self.map = map
            userDirection.attach(to: map, project: { [weak map] in
                guard let map, let location = map.myLocation else { return nil }
                return map.projection.point(for: location.coordinate)
            }, bearing: { [weak map] in map?.camera.bearing ?? 0 })
            userDirection.onHeading = { [weak self, weak map] _ in
                guard let self, let map, self.store.locationMode == .heading else { return }
                self.centerUser(map, animated: false)
            }
            if locationObservation == nil {
                locationObservation = map.observe(\.myLocation, options: [.new]) { [weak self, weak map] _, _ in
                    Task { @MainActor in
                        guard let self, let map else { return }
                        self.locate(map); self.userDirection.refresh()
                    }
                }
            }
            var desired: [String: (Coordinate, String, Marker?)] = [:]
            for marker in store.mapMarkers { desired["saved/" + marker.id] = (marker.coordinates, marker.title, marker) }
            for place in store.searchResults { desired["search/" + place.id] = (place.coordinates, place.name, nil) }
            if poiInfoMarker != nil, store.draft?.id != poiDraftID {
                poiInfoMarker?.map = nil; poiInfoMarker = nil; poiDraftID = nil
            }
            if let draft = store.draft, poiInfoMarker == nil { desired["draft"] = (draft.coordinates, draft.title, nil) }
            for key in Array(markers.keys) where desired[key] == nil {
                guard let marker = markers.removeValue(forKey: key) else { continue }
                if key == "draft" { MapInteractionFeedback.disappear(marker.iconView) { marker.map = nil } }
                else { marker.map = nil }
            }
            for (key, value) in desired {
                let marker = markers[key] ?? GMSMarker()
                marker.position = Self.coordinate(value.0); marker.title = value.1; marker.userData = key
                marker.groundAnchor = CGPoint(x: 0.5, y: key == "draft" ? 42.0/48.0 : value.2 == nil ? 1 : 0.5)
                marker.zIndex = key == "draft" ? 1000 : value.2 != nil && store.selectedMarker?.id == value.2?.id ? 3 : key.hasPrefix("saved/") ? 2 : 1
                if let saved = value.2 {
                    marker.icon = MapMarkerAppearance.image(icon: saved.icon, compact: MapZoomPresentation.isCompact(Double(map.camera.zoom)), selected: store.selectedMarker?.id == saved.id)
                } else if key == "draft" { marker.icon = MapMarkerAppearance.draftImage(icon: store.draft?.icon ?? .location) }
                else { marker.icon = SearchPinAppearance.image(selected: store.editingSearchPlaceID == String(key.dropFirst(7))) }
                if key == "draft" {
                    let first = marker.iconView == nil
                    let view = (marker.iconView as? UIImageView) ?? UIImageView()
                    view.image = marker.icon; view.bounds.size = CGSize(width: 44, height: 48)
                    marker.iconView = view
                    marker.tracksViewChanges = first
                    if first {
                        MapInteractionFeedback.appear(view)
                        DispatchQueue.main.asyncAfter(deadline: .now() + MapInteractionFeedback.duration) { [weak marker] in marker?.tracksViewChanges = false }
                    }
                }
                marker.map = map; markers[key] = marker
            }
            let snapshot = store.displayRoutes.map(RouteOverlayGeometry.init)
            if snapshot != geometries {
                geometries = snapshot
                for line in Array(lines.values) + Array(casings.values) { line.map = nil }; lines = [:]; casings = [:]
                for geometry in snapshot {
                    let path = GMSMutablePath()
                    for point in geometry.points { path.add(Self.coordinate(point)) }
                    let casing = GMSPolyline(path: path)
                    casing.strokeWidth = RouteLineAppearance.outlineWidth(selected: false)
                    casing.strokeColor = RouteLineAppearance.outline(geometry.colorIndex); casing.isTappable = false; casing.zIndex = 0
                    casing.map = map; casings[geometry.id] = casing
                    let line = GMSPolyline(path: path)
                    line.zIndex = 1
                    line.strokeWidth = RouteLineAppearance.width(selected: false); line.strokeColor = RouteLineAppearance.color(geometry.colorIndex)
                    line.userData = geometry.id; line.isTappable = !store.placeSearchPresented
                    line.map = map; lines[geometry.id] = line
                }
            }
            for line in lines.values { line.isTappable = !store.placeSearchPresented; line.map = MapZoomPresentation.isCompact(Double(map.camera.zoom)) ? nil : map }
            let selected = store.displayRoutes.filter { $0.dayID == store.dayID }
            let selectedIDs = Set(selected.map(\.id))
            for (id, line) in lines {
                line.strokeWidth = RouteLineAppearance.width(selected: selectedIDs.contains(id))
                casings[id]?.strokeWidth = RouteLineAppearance.outlineWidth(selected: selectedIDs.contains(id))
                casings[id]?.map = line.map
            }
            routeMotion.update(routes: selected, in: map, enabled: { [weak self, weak map] in
                guard let self, let map else { return false }
                return !MapZoomPresentation.isCompact(Double(map.camera.zoom)) && !self.store.placeSearchPresented
            }, project: { [weak map] coordinate in
                map?.projection.point(for: Self.coordinate(coordinate)) ?? .zero
            }, unproject: { [weak map] point in
                let coordinate = map?.projection.coordinate(for: point) ?? CLLocationCoordinate2D()
                return Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }, cameraKey: { [weak map] in Double(map?.camera.zoom ?? 0) }, publish: { [weak self, weak map] paths in
                guard let self, let map else { return }
                self.directionLines.forEach { $0.map = nil }
                self.directionLines = paths.map { points in
                    let path = GMSMutablePath(); points.forEach { path.add(Self.coordinate($0)) }
                    let line = GMSPolyline(path: path)
                    line.strokeColor = RouteMotionOverlay.strokeColor; line.strokeWidth = RouteMotionOverlay.strokeWidth
                    line.isTappable = false; line.zIndex = 2; line.map = map; return line
                }
            })
            map.isBuildingsEnabled = !store.placeSearchPresented
            // Hide commercial POIs during server search; road labels remain visible.
            if searchStyleEnabled != store.placeSearchPresented {
                searchStyleEnabled = store.placeSearchPresented
                map.mapStyle = store.placeSearchPresented ? try? GMSMapStyle(jsonString: "[{\"featureType\":\"poi\",\"stylers\":[{\"visibility\":\"off\"}]}]") : nil
            }
            if let command = store.camera, command.id != lastCamera { lastCamera = command.id; focus(map, command) }
            headingManager.stopUpdatingHeading()
            if lastLocate == nil { lastLocate = store.locating }
            else if lastLocate != store.locating {
                lastLocate = store.locating; pendingLocate = true; map.isMyLocationEnabled = true; locate(map)
            }
        }
        func focus(_ map: GMSMapView, _ command: CameraCommand) {
            guard let first = command.points.first else { return }
            let insets = command.viewportInsets(base: store.mapViewportInsets, height: map.bounds.height,
                bottomSafeArea: map.safeAreaInsets.bottom, bottomSheet: UIDevice.current.userInterfaceIdiom != .pad)
            map.padding = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            if command.revealDraft {
                let screen = map.projection.point(for: Self.coordinate(first))
                let padding = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
                let target = MapInteractionFeedback.revealTarget(screen, bounds: map.bounds, insets: padding)
                let update = GMSCameraUpdate.scrollBy(x: screen.x - target.x, y: screen.y - target.y)
                if UIAccessibility.isReduceMotionEnabled { map.moveCamera(update) } else { map.animate(with: update) }
                return
            }
            if command.points.count == 1 {
                let camera = GMSCameraPosition(target: Self.coordinate(first), zoom: command.revealDraft ? map.camera.zoom : Float(command.singlePointZoom))
                if UIAccessibility.isReduceMotionEnabled { map.camera = camera } else { map.animate(to: camera) }
            } else {
                var bounds = GMSCoordinateBounds(coordinate: Self.coordinate(first), coordinate: Self.coordinate(first))
                for point in command.points.dropFirst() { bounds = bounds.includingCoordinate(Self.coordinate(point)) }
                let update = GMSCameraUpdate.fit(bounds, withPadding: 20)
                if UIAccessibility.isReduceMotionEnabled { map.moveCamera(update) } else { map.animate(with: update) }
            }
        }
        func locate(_ map: GMSMapView) {
            guard pendingLocate, let location = map.myLocation, location.horizontalAccuracy >= 0 else { return }
            pendingLocate = false
            centerUser(map, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        private func centerUser(_ map: GMSMapView, animated: Bool) {
            guard let location = map.myLocation else { return }
            let insets = store.mapViewportInsets
            map.padding = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            let camera = GMSCameraPosition(target: location.coordinate, zoom: 15,
                bearing: store.locationMode == .heading ? (userDirection.heading ?? map.camera.bearing) : 0, viewingAngle: 0)
            if animated { map.animate(to: camera) } else { map.camera = camera }
            userDirection.refresh()
        }
        func stopHeading() { headingManager.stopUpdatingHeading() }
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            store.noteMapInteraction(); tapArbiter.claim()
            guard let key = marker.userData as? String else { return true }
            if key.hasPrefix("saved/"), let value = store.mapMarkers.first(where: { "saved/" + $0.id == key }) { store.focus(value) }
            else if key.hasPrefix("search/"), let place = store.searchResults.first(where: { "search/" + $0.id == key }) { store.choose(place, fromMap: true) }
            return true
        }
        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            poiInfoMarker?.map = nil; poiInfoMarker = nil; poiDraftID = nil
            store.noteMapInteraction(); store.create(at: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
            guard !store.placeSearchPresented else { return }
            let point = mapView.projection.point(for: location)
            if let saved = store.mapMarkers.first(where: { marker in
                let screen = mapView.projection.point(for: Self.coordinate(marker.coordinates))
                return abs(screen.x - point.x) <= 22 && abs(screen.y - point.y) <= 22
            }) {
                tapArbiter.claim(); store.focus(saved); return
            }
            tapArbiter.claim()
            store.noteMapInteraction(); store.create(at: Coordinate(latitude: location.latitude, longitude: location.longitude), poiName: name, placeReferences: PlaceReferences(google: PlaceReference(placeId: placeID)))
            poiInfoMarker?.map = nil
            let info = GMSMarker(position: location)
            info.title = name
            info.icon = UIImage() // Google's documented POI info-window pattern.
            info.map = mapView; mapView.selectedMarker = info
            poiInfoMarker = info; poiDraftID = store.draft?.id
        }
        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            guard !store.placeSearchPresented, let id = overlay.userData as? String, let route = store.displayRoutes.first(where: { $0.id == id }) else { return }
            store.noteMapInteraction()
            tapArbiter.scheduleRoute { [weak self] in self?.store.selectRoute(route) }
        }
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) { if gesture { store.noteMapInteraction() } }
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) { routeMotion.refresh(); userDirection.refresh() }
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            update(mapView)
            let region = mapView.projection.visibleRegion()
            let points = [region.farLeft, region.farRight, region.nearLeft, region.nearRight]
            store.bounds = SearchBounds(west: points.map(\.longitude).min()!, south: points.map(\.latitude).min()!, east: points.map(\.longitude).max()!, north: points.map(\.latitude).max()!)
        }
    }
}
