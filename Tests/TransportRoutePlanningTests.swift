import XCTest
import Combine
import MapKit
@testable import MapAnNai

final class TransportRoutePlanningTests: XCTestCase {
    func testOnlyActiveDirectedVisitProvidesTransportAndInvalidatesOldGeometry() async throws {
        let processing = RouteProcessing()
        let a = Coordinate(latitude:31, longitude:121), b = Coordinate(latitude:31.01, longitude:121.01)
        let markers = [Marker(id:"a", coordinates:a, content:MarkerContent(id:"a",markdownContent:"")),
                       Marker(id:"b", coordinates:b, content:MarkerContent(id:"b",markdownContent:""))]
        let stops = [ChainStop(id:"visit-a",markerId:"a"), ChainStop(id:"visit-b",markerId:"b")]
        var chain = RouteChain(id:"chain",stops:stops,legs:[ChainLeg(fromStopId:"visit-a",toStopId:"visit-b",mode:.train)])
        var day = TripDay(id:"day",tripId:"trip",date:"2026-10-05",markerIds:["a","b"],chains:[["a","b"]],routeChains:[chain])
        let initial = try await processing.build(days:[day],markers:markers,selectedTrip:nil,previous:[],preserve:true)
        XCTAssertEqual(initial[0].display.transportMode,.train)
        var old = initial[0].display; old.isPlanned = true
        chain.legs[0].mode = .walking; day.routeChains = [chain]
        let changed = try await processing.build(days:[day],markers:markers,selectedTrip:nil,previous:[old],preserve:true)
        XCTAssertEqual(changed[0].display.transportMode,.walking)
        XCTAssertFalse(changed[0].display.isPlanned)
        day.chains = [["b","a"]]; day.routeChains = [chain.reordered(to:["b","a"])]
        let reversed = try await processing.build(days:[day],markers:markers,selectedTrip:nil,previous:[old],preserve:true)
        XCTAssertNil(reversed[0].display.transportMode)
    }
    @MainActor func testMissingAndFailedPlanningStayDashedUntilPlanningIsDisabled() async throws {
        let settings = Settings(), original = Settings().planning
        settings.planning = true
        defer { settings.planning = original }
        let demo = AppStore(settings:settings,demo:true)
        await demo.awaitRouteUpdates()
        let trip = try XCTUnwrap(demo.trip)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = AppStore(settings:settings,demo:false,services:FailedPlanningService(),routeCache:RouteCache(directory:directory))
        store.markers = demo.markers; store.trips = [trip]
        var missingWasDashed = true
        let observation = store.$displayRoutes.dropFirst().sink { routes in
            if routes.contains(where: { !$0.isPlanned && !$0.isDashed }) { missingWasDashed = false }
        }
        store.select(trip:trip,day:trip.days[0],focus:false)
        await store.awaitRouteUpdates()
        observation.cancel()
        XCTAssertFalse(store.displayRoutes.isEmpty)
        XCTAssertNotNil(store.routeError)
        XCTAssertTrue(missingWasDashed)
        XCTAssertTrue(store.displayRoutes.allSatisfy { $0.isDashed && !$0.isPlanned })
        settings.planning = false
        store.rebuildRoutes()
        await store.awaitRouteUpdates()
        XCTAssertTrue(store.displayRoutes.allSatisfy { !$0.isDashed && !$0.isPlanned })
    }
    @MainActor func testNativeAppleDashGapsSurviveSelectedCasingWidth() async throws {
        let store = AppStore(settings:Settings(),demo:true)
        await store.awaitRouteUpdates()
        let coordinator = AppleMapRenderer.Coordinator(store)
        let map = MKMapView()
        var points = [CLLocationCoordinate2D(latitude:31,longitude:121),CLLocationCoordinate2D(latitude:31.01,longitude:121.01)]
        for selected in [false,true] {
            for casing in [false,true] {
                let line = AppleMapRenderer.Line(coordinates:&points,count:points.count)
                line.dayID = selected ? (store.dayID ?? "") : "unselected"
                line.casing = casing; line.isDashed = true
                let renderer = try XCTUnwrap(coordinator.mapView(map,rendererFor:line) as? MKPolylineRenderer)
                XCTAssertEqual(renderer.lineWidth, (selected ? 6 : 3.5) + (casing ? 2 : 0))
                XCTAssertNil(renderer.lineDashPattern)
                XCTAssertEqual(renderer.lineCap,.butt, "Round caps consume the 6pt gap when selected")
            }
        }
    }
    @MainActor func testDashedRouteVisualReview() async throws {
        let store = AppStore(settings:Settings(),demo:true)
        await store.awaitRouteUpdates()
        let coordinator = AppleMapRenderer.Coordinator(store)
        let window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        let map = MKMapView(frame:window.bounds)
        let controller = UIViewController(); controller.view = map
        window.rootViewController = controller; window.makeKeyAndVisible()
        map.delegate = coordinator
        map.setRegion(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:31.23,longitude:121.47),latitudinalMeters:1800,longitudinalMeters:1200),animated:false)
        let points = RouteGeometry.curve(Coordinate(latitude:31.225,longitude:121.466),Coordinate(latitude:31.235,longitude:121.474))
        for before in [true,false] {
            map.removeOverlays(map.overlays)
            coordinator.routes = [DisplayRoute(id:"review",dayID:store.dayID ?? "",tripID:"trip",colorIndex:0,points:points,isPlanned:false,isDashed:true)]
            coordinator.dashScale = 0
            if before {
                var coordinates = points.map(AppleMapRenderer.Pin.coordinate)
                let line = AppleMapRenderer.Line(coordinates:&coordinates,count:coordinates.count)
                line.dayID = store.dayID ?? ""; line.isDashed = true
                map.addOverlay(line)
            } else { coordinator.updateDashedRoutes(map) }
            try await Task.sleep(for:.seconds(2))
            if before {
                for overlay in map.overlays {
                    if let line = overlay as? AppleMapRenderer.Line, let renderer = map.renderer(for:line) as? MKPolylineRenderer {
                        renderer.lineWidth = 3
                        renderer.lineDashPattern = [8,6]
                        renderer.setNeedsDisplay()
                    }
                }
            }
            try await Task.sleep(for:.milliseconds(250))
            let image = UIGraphicsImageRenderer(bounds:map.bounds).image { _ in map.drawHierarchy(in:map.bounds,afterScreenUpdates:true) }
            let attachment = XCTAttachment(image:image)
            attachment.name = before ? "Before native dash pattern" : "After solid segments"
            attachment.lifetime = .keepAlways; add(attachment)
            if !before {
                let initial = map.camera.centerCoordinateDistance
                for (step,factor) in [0.55,1.4].enumerated() {
                    let camera = map.camera.copy() as! MKMapCamera
                    camera.centerCoordinateDistance = initial*factor
                    map.setCamera(camera,animated:true)
                    for frame in 0..<10 {
                        try await Task.sleep(for:.milliseconds(100))
                        for overlay in map.overlays {
                            if let line = overlay as? AppleMapRenderer.Line, let renderer = map.renderer(for:line) as? MKPolylineRenderer {
                                XCTAssertNil(renderer.lineDashPattern)
                                XCTAssertEqual(renderer.lineWidth,line.casing ? 8 : 6)
                            }
                        }
                        if frame == 3 || frame == 9 {
                            let image = UIGraphicsImageRenderer(bounds:map.bounds).image { _ in map.drawHierarchy(in:map.bounds,afterScreenUpdates:true) }
                            let capture = XCTAttachment(image:image); capture.name = "Zoom-\(step)-\(frame)"; capture.lifetime = .keepAlways; add(capture)
                        }
                    }
                }
            }
        }
        window.isHidden = true
    }
    func testDashSegmentsKeepPhaseAndScreenLengthsAcrossZoomAndClipping() {
        let path = [CGPoint(x:0,y:0),CGPoint(x:10000,y:0)]
        for scale in [0.5,1.0,4.0] {
            let segments = RouteDashGeometry.segments(path,unitsPerPoint:scale,clip:CGRect(x:100,y:-10,width:500,height:20))
            XCTAssertFalse(segments.isEmpty)
            for segment in segments {
                XCTAssertLessThanOrEqual((segment.last!.x-segment.first!.x)/scale,8.000001)
                let phase = segment.first!.x.truncatingRemainder(dividingBy:14*scale)
                XCTAssertTrue(abs(phase) < 0.00001 || abs(segment.first!.x-100) < 0.00001)
            }
        }
        let corner = RouteDashGeometry.segments([.zero,CGPoint(x:4,y:0),CGPoint(x:4,y:20)],unitsPerPoint:1,clip:CGRect(x:-10,y:-10,width:50,height:50))
        XCTAssertEqual(corner[0],[.zero,CGPoint(x:4,y:0),CGPoint(x:4,y:4)])
    }
    @MainActor func testCompactConnectionsScreenshot() async throws {
        let store = AppStore(settings:Settings(),demo:true)
        await store.awaitRouteUpdates()
        let window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:700))
        let map = MKMapView(frame:window.bounds)
        let controller = UIViewController(); controller.view = map
        window.rootViewController = controller; window.makeKeyAndVisible()
        let coordinator = AppleMapRenderer.Coordinator(store); map.delegate = coordinator
        coordinator.compact = true
        let points = [Coordinate(latitude:31.1,longitude:121.2),Coordinate(latitude:31.4,longitude:121.5),Coordinate(latitude:31.15,longitude:121.75)]
        map.setRegion(MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:31.25,longitude:121.45),latitudinalMeters:90000,longitudinalMeters:65000),animated:false)
        for i in 1..<points.count {
            let route = DisplayRoute(id:"test",dayID:"",tripID:"",colorIndex:0,points:RouteGeometry.curve(points[i-1],points[i]),isPlanned:false)
            let endpoints = MapZoomPresentation.endpoints(route)
            XCTAssertEqual(endpoints,[points[i-1],points[i]])
            var coordinates = endpoints.map(AppleMapRenderer.Pin.coordinate)
            let line = AppleMapRenderer.Line(coordinates:&coordinates,count:2); line.overview = true
            map.addOverlay(line,level:.aboveRoads)
        }
        for (i,point) in points.enumerated() {
            let pin = AppleMapRenderer.Pin(key:"test-\(i)",coordinate:point,title:"地点")
            pin.marker = Marker(id:"test-\(i)",coordinates:point,content:MarkerContent(id:"test-\(i)",markdownContent:""))
            map.addAnnotation(pin)
        }
        try await Task.sleep(for:.seconds(3))
        coordinator.compact = true
        for overlay in map.overlays {
            if let renderer = map.renderer(for:overlay) as? MKPolylineRenderer {
                renderer.alpha = 1; XCTAssertEqual(renderer.lineWidth,1)
            }
        }
        let image = UIGraphicsImageRenderer(bounds:map.bounds).image { _ in map.drawHierarchy(in:map.bounds,afterScreenUpdates:true) }
        let attachment = XCTAttachment(image:image); attachment.name = "Compact 1pt connections"; attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true
    }
    func testFallbackIsDashedAndTransitExpirySurvivesDiskReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache = RouteCache(directory:directory), processing = RouteProcessing()
        let a = Coordinate(latitude:31,longitude:121), b = Coordinate(latitude:31.01,longitude:121.01)
        let key = RouteCache.key(a,b,mode:.train)
        var display = DisplayRoute(id:"leg",dayID:"day",tripID:"trip",colorIndex:0,points:[a,b],isPlanned:false)
        display.transportMode = .train
        for reason in ["NO_ROUTE","UNSUPPORTED_MODE","UNSUPPORTED_REGION","OVER_DIRECTION_RANGE"] {
            let route = PlannedRoute(path:[RoutePoint(lat:a.latitude,lng:a.longitude),RoutePoint(lat:b.latitude,lng:b.longitude)],distance:100,duration:nil,fallback:reason,distanceKind:"straight")
            await cache.put(route,key:key)
            let restored = try await processing.restoringCachedGeometry([RouteSegment(display:display,origin:a,destination:b)],cache:cache,provider:.amap,server:"")
            XCTAssertTrue(restored[0].display.isDashed)
            XCTAssertFalse(restored[0].display.isPlanned)
            XCTAssertNil(restored[0].display.distance)
            XCTAssertEqual(restored[0].display.points,RouteGeometry.curve(a,b))
            let future = Date().addingTimeInterval(3601)
            let memory = await cache.get(key,now:future)
            let disk = await RouteCache(directory:directory).get(key,now:future)
            XCTAssertEqual(memory == nil, reason == "NO_ROUTE")
            XCTAssertEqual(disk == nil, reason == "NO_ROUTE")
        }
        let success = PlannedRoute(path:[RoutePoint(lat:a.latitude,lng:a.longitude),RoutePoint(lat:b.latitude,lng:b.longitude)],distance:100,duration:20)
        await cache.put(success,key:key)
        let expired = await cache.get(key,now:Date().addingTimeInterval(3601))
        XCTAssertNil(expired)
    }
}

private struct FailedPlanningService: MapServices {
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] { [] }
    func details(at coordinate: Coordinate) async throws -> Place { throw AppError.message("Unused") }
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TransportMode?) async throws -> PlannedRoute {
        throw AppError.message("Test offline response")
    }
}
