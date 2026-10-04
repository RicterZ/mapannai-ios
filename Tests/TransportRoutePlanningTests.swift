import XCTest
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
