import XCTest
@testable import MapAnNai

final class CoreTests: XCTestCase {
    func testEmptyTiptapNotesAndMediaContent() {
        for html in ["", "  ", "<p></p>", "<p><br></p>", "<p>&nbsp; &#160; &#xA0;\u{200B}</p>", "<!-- draft -->", "<style>p {color:red}</style>"] {
            XCTAssertFalse(NoteContent.hasContent(html), html)
        }
        for html in ["<p>笔记</p>", "<p>&amp;</p>", "<img src='https://example.com/a.png'>", "<p><strong>0</strong></p>"] {
            XCTAssertTrue(NoteContent.hasContent(html), html)
        }
    }
    @MainActor func testRepeatedPlaceSelectionUsesFixedZoomWithoutAnotherCameraCommand() {
        let store = AppStore(settings: Settings(), demo: true)
        let marker = store.markers[0]
        store.focus(marker)
        XCTAssertEqual(store.camera?.zoomLevel, 15)
        let firstID = store.camera?.id
        store.focus(marker)
        XCTAssertEqual(store.camera?.id, firstID)
        store.selectedMarker = nil
        store.focus(marker)
        XCTAssertEqual(store.camera?.zoomLevel, 15)
        XCTAssertEqual(store.camera?.points, [marker.coordinates])
        XCTAssertNotEqual(store.camera?.id, firstID)
    }
    func testUpcomingTripFirstStopIncludesTodayAndSkipsTripsWithoutValidPlaces() {
        func marker(_ id: String, _ latitude: Double = 31) -> Marker {
            Marker(id: id, coordinates: Coordinate(latitude: latitude, longitude: 121),
                   content: MarkerContent(id: id, markdownContent: ""))
        }
        func trip(_ id: String, _ date: String, _ ids: [String]) -> Trip {
            Trip(id: id, name: id, startDate: date, endDate: date,
                 days: [TripDay(id: id + "-day", tripId: id, date: date, markerIds: ids, chains: [])])
        }
        let markers = [marker("past"), marker("invalid", 100), marker("first"), marker("second"), marker("future")]
        let trips = [trip("later", "2026-10-02", ["future"]), trip("past", "2026-09-29", ["past"]),
                     trip("a-empty", "2026-09-30", ["missing", "invalid"]), trip("b-today", "2026-09-30", ["first", "second"])]
        XCTAssertEqual(StartupCamera.upcomingFirstMarker(trips: trips, markers: markers, today: "2026-09-30")?.id, "first")
        XCTAssertEqual(StartupCamera.upcomingFirstMarker(trips: trips, markers: markers, today: "2026-10-01")?.id, "future")
        XCTAssertNil(StartupCamera.upcomingFirstMarker(trips: trips, markers: markers, today: "2026-10-03"))
    }
    func testStartupDateUsesDeviceTimezoneAtMidnight() {
        let now = ISO8601DateFormatter().date(from: "2026-09-30T18:00:00Z")!
        var east = Calendar(identifier: .gregorian); east.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var west = Calendar(identifier: .gregorian); west.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        XCTAssertEqual(StartupCamera.localDate(now: now, calendar: east), "2026-10-01")
        XCTAssertEqual(StartupCamera.localDate(now: now, calendar: west), "2026-09-30")
    }
    @MainActor func testStartupFocusesFirstStopOnceWithoutSelectingAnything() {
        let store = AppStore(settings: Settings(), demo: false)
        let sample = AppStore(settings: Settings(), demo: true)
        store.markers = sample.markers; store.trips = sample.trips
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        store.applyStartupCamera(now: now, calendar: calendar)
        XCTAssertEqual(store.camera?.points, [sample.markers[0].coordinates])
        XCTAssertEqual(store.camera?.zoomLevel, 11)
        XCTAssertNil(store.tripID); XCTAssertNil(store.dayID); XCTAssertNil(store.selectedMarker)
        XCTAssertEqual(store.visibleMarkers.count, 5)
        store.focus(store.markers[0])
        let camera = store.camera?.id
        store.applyStartupCamera(now: now, calendar: calendar)
        XCTAssertEqual(store.camera?.id, camera)
        XCTAssertEqual(store.selectedMarker?.id, store.markers[0].id)
    }
    @MainActor func testStartupSingleStopUsesOverviewZoomAndNoUpcomingTripKeepsCamera() {
        let store = AppStore(settings: Settings(), demo: false)
        let sample = AppStore(settings: Settings(), demo: true)
        store.markers = [sample.markers[0]]; store.trips = sample.trips
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!
        store.applyStartupCamera(now: now, calendar: calendar)
        XCTAssertEqual(store.camera?.zoomLevel, 11)
        XCTAssertNil(store.tripID); XCTAssertNil(store.dayID); XCTAssertNil(store.selectedMarker)
        let empty = AppStore(settings: Settings(), demo: false)
        empty.markers = sample.markers; empty.trips = sample.trips
        empty.applyStartupCamera(now: now.addingTimeInterval(7 * 86400), calendar: calendar)
        XCTAssertNil(empty.camera)
    }
    @MainActor func testStartupDoesNotInterruptAnExistingSelection() {
        let store = AppStore(settings: Settings(), demo: false)
        let sample = AppStore(settings: Settings(), demo: true)
        store.markers = sample.markers; store.trips = sample.trips
        store.focus(store.markers[0])
        let camera = store.camera?.id
        store.applyStartupCamera()
        XCTAssertEqual(store.camera?.id, camera)
        XCTAssertEqual(store.selectedMarker?.id, store.markers[0].id)
    }
    func testCoordinateRoundtripAndOverseasIdentity() {
        for point in [Coordinate(latitude: 31.2304, longitude: 121.4737), Coordinate(latitude: 39.9042, longitude: 116.4074)] {
            let converted = Coordinates.gcj(point)
            XCTAssertGreaterThan(Coordinates.distance(point, converted), 100)
            XCTAssertLessThan(Coordinates.distance(point, Coordinates.wgs(converted)), 3)
        }
        let tokyo = Coordinate(latitude: 35.6762, longitude: 139.6503)
        XCTAssertEqual(Coordinates.gcj(tokyo), tokyo)
        XCTAssertEqual(Coordinates.wgs(tokyo), tokyo)
    }
    func testRemovingMarkerCleansEveryChainAndKeepsSharedRoutes() throws {
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-01", colorIndex: 4, markerIds: ["a","b","c","d"], chains: [["a","b","c"],["b","d"],["b"]])
        let changed = day.removing("b")
        XCTAssertEqual(changed.markerIds, ["a","c","d"])
        XCTAssertEqual(changed.chains, [["a","c"],["d"]])
        XCTAssertEqual(changed.colorIndex, 4)
        let new = try day.replacingChain(at: nil, with: ["b","e"])
        XCTAssertEqual(new.markerIds, ["a","b","c","d","e"])
        XCTAssertEqual(new.chains.last, ["b","e"])
        XCTAssertEqual(new.chains.first, ["a","b","c"])
        XCTAssertThrowsError(try day.replacingChain(at: nil, with: ["a","a"]))
        XCTAssertThrowsError(try day.replacingChain(at: 3, with: ["a","c"]))
    }
    func testDisplayGeometryPreservesEndpointsAndInput() {
        let a = Coordinate(latitude: 31.2, longitude: 121.4), b = Coordinate(latitude: 31.21, longitude: 121.41)
        let middle = Coordinate(latitude: 31.22, longitude: 121.42)
        let raw = [a, a, middle, b], copy = raw
        let smooth = RouteGeometry.smooth(raw)
        XCTAssertEqual(raw, copy)
        XCTAssertEqual(smooth.first, a); XCTAssertEqual(smooth.last, b)
        XCTAssertTrue(smooth.allSatisfy(\.isValid))
        let curve = RouteGeometry.curve(a,b)
        XCTAssertEqual(curve.first, a); XCTAssertEqual(curve.last,b)
        XCTAssertGreaterThan(curve.count, 2)
    }
    func testScreenRoutePickingUsesDistanceNotLayerOrder() {
        XCTAssertEqual(RouteGeometry.nearestDistance((5,4), to: [(0,0),(10,0)]), 4, accuracy: 0.0001)
        XCTAssertEqual(RouteGeometry.nearestDistance((5,4), to: [(0,5),(10,5)]), 1, accuracy: 0.0001)
        XCTAssertEqual(RouteGeometry.nearestDistance((0,0), to: []), .infinity)
    }
    @MainActor func testPersistentCacheSeparatesModesDirectionsAndCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = Coordinate(latitude: 31.2, longitude: 121.4), b = Coordinate(latitude: 31.21, longitude: 121.41)
        let key = RouteCache.key(a,b,mode: .walking)
        XCTAssertNotEqual(key, RouteCache.key(a,b,mode: .driving))
        XCTAssertNotEqual(key, RouteCache.key(b,a,mode: .walking))
        let route = PlannedRoute(path: [.init(lat: a.latitude,lng: a.longitude), .init(lat: b.latitude,lng: b.longitude)], distance: 1234, duration: 456)
        RouteCache(directory: directory).put(route,key: key)
        let reloaded = RouteCache(directory: directory).get(key)
        XCTAssertEqual(reloaded?.path, route.path)
        XCTAssertEqual(reloaded?.distance, 1234); XCTAssertEqual(reloaded?.duration, 456)
    }
    func testWebMarkerAndTripContracts() throws {
        let markerJSON = #"[{"id":"coord_example","coordinates":{"latitude":31.2,"longitude":121.4},"content":{"id":"coord_example","title":"地点","iconType":"food","markdownContent":"<p>笔记</p>","createdAt":"2026-09-30T00:00:00.000Z","next":[]}}]"#
        let markers = try JSONDecoder().decode([Marker].self, from: Data(markerJSON.utf8))
        XCTAssertEqual(markers.first?.icon, .food)
        XCTAssertEqual(markers.first?.content.markdownContent, "<p>笔记</p>")
        let tripJSON = #"[{"id":"t","name":"旅行","startDate":"2026-10-01","endDate":"2026-10-01","days":[{"id":"d","tripId":"t","date":"2026-10-01","markerIds":[],"chains":[],"colorIndex":5}]}]"#
        let trips = try JSONDecoder().decode([Trip].self, from: Data(tripJSON.utf8))
        XCTAssertEqual(trips.first?.days.first?.colorIndex,5)
    }
}
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class APIClientTests: XCTestCase {
    func testBearerTokenAndAPIPath() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://example.invalid/map",token: "test-only",session: URLSession(configuration: config))
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/map/api/trips")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
            return (200, Data("[]".utf8))
        }
        let trips: [Trip] = try await client.request("trips")
        XCTAssertTrue(trips.isEmpty)
    }
    func testUnauthorizedReturnsActionableError() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://example.invalid",token: "",session: URLSession(configuration: config))
        MockURLProtocol.handler = { _ in (401, Data(#"{"error":"Unauthorized"}"#.utf8)) }
        do { let _: [Trip] = try await client.request("trips"); XCTFail("Expected authentication failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("token")) }
    }
}
final class MapServiceTests: XCTestCase {
    private func services(handler: @escaping (URLRequest) throws -> (Int, Data)) -> ServerMapServices {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return ServerMapServices(client: APIClient(baseURL: "https://example.invalid", token: "test-only", session: URLSession(configuration: config)), configuration: .current)
    }
    func testSearchEncodesQueryAndExpandedBounds() async throws {
        let services = services { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(parts.path, "/api/search")
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "q" })?.value, "上海 美食 & 咖啡")
            let bounds = parts.queryItems!.first(where: { $0.name == "bounds" })!.value!
            let decoded = try JSONDecoder().decode(SearchBounds.self, from: Data(bounds.utf8))
            XCTAssertEqual(decoded.west, 120.8, accuracy: 0.001)
            XCTAssertEqual(decoded.east, 122.2, accuracy: 0.001)
            return (200, Data(#"{"success":true,"data":[{"id":"名称","placeId":"poi-id","name":"咖啡","address":"上海","coordinates":{"latitude":31.2,"longitude":121.4}}]}"#.utf8))
        }
        let places = try await services.search("上海 美食 & 咖啡", bounds: .init(west:121,south:31,east:122,north:32))
        XCTAssertEqual(places.first?.id, "poi-id")
        XCTAssertEqual(places.first?.coordinates.latitude, 31.2)
    }
    func testDirectionsUsesServerAndWGSCoordinates() async throws {
        let services = services { request in
            XCTAssertEqual(request.url?.path, "/api/directions"); XCTAssertEqual(request.httpMethod,"POST")
            let body = requestBody(request)
            let object = try JSONSerialization.jsonObject(with: body) as! [String:Any]
            XCTAssertEqual(object["mode"] as? String, "driving")
            XCTAssertEqual((object["origin"] as? [String:Double])?["lat"], 31.2)
            XCTAssertEqual((object["destination"] as? [String:Double])?["lng"], 121.5)
            return (200,Data(#"{"path":[{"lat":31.2,"lng":121.4},{"lat":31.3,"lng":121.5}],"distance":100,"duration":20}"#.utf8))
        }
        let route = try await services.route(.init(latitude:31.2,longitude:121.4), .init(latitude:31.3,longitude:121.5), mode:.driving)
        XCTAssertEqual(route.path.count,2); XCTAssertEqual(route.distance,100)
    }
    func testDetailsUsesServerAndClickedWGSCoordinates() async throws {
        let services = services { request in
            XCTAssertEqual(request.url?.path, "/api/places")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Double]
            XCTAssertEqual(body["latitude"], 31.2); XCTAssertEqual(body["longitude"], 121.4)
            return (200, Data(#"{"success":true,"data":{"name":"返回的地点","address":"返回的地址","coordinates":{"latitude":31.201,"longitude":121.401}}}"#.utf8))
        }
        let place = try await services.details(at: Coordinate(latitude: 31.2, longitude: 121.4))
        XCTAssertEqual(place.name, "返回的地点"); XCTAssertEqual(place.address, "返回的地址")
    }
    func testRouteFallbackServerResponseAcceptsNullMetrics() async throws {
        let services = services { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["mode"] as? String, "driving")
            return (200, Data(#"{"path":[{"lat":31,"lng":121},{"lat":35,"lng":139}],"distance":null,"duration":null,"fallback":"UNSUPPORTED_REGION"}"#.utf8))
        }
        let route = try await services.route(.init(latitude:31, longitude:121), .init(latitude:35, longitude:139), mode: .auto)
        XCTAssertTrue(route.isFallback); XCTAssertNil(route.distance)
    }
    @MainActor func testConfigurationSourceAndCacheProviderIsolation() async throws {
        let source = FixedMapConfigurationSource(configuration: .init(renderer: .google, searchProvider: .amap, detailsProvider: .amap, directionsProvider: .google))
        let config = try await source.load(using: APIClient(baseURL:"https://example.invalid",token:""))
        XCTAssertEqual(config.renderer,.google)
        XCTAssertNil(MapRendererRegistry.renderer(for: .google))
        XCTAssertNotNil(MapRendererRegistry.renderer(for: .amap))
        let a = Coordinate(latitude:31.2,longitude:121.4), b = Coordinate(latitude:31.3,longitude:121.5)
        XCTAssertNotEqual(RouteCache.key(a,b,mode:.walking,provider:.amap),RouteCache.key(a,b,mode:.walking,provider:.google))
        XCTAssertNotEqual(RouteCache.key(a,b,mode:.walking,server:"https://one.invalid"),RouteCache.key(a,b,mode:.walking,server:"https://two.invalid"))
    }
    @MainActor func testServerURLValidationRejectsCredentials() throws {
        XCTAssertEqual(try Settings.normalizedURL(" https://example.invalid/api/ "), "https://example.invalid")
        XCTAssertThrowsError(try Settings.normalizedURL("https://user:secret@example.invalid"))
        XCTAssertThrowsError(try Settings.normalizedURL("https://example.invalid?token=secret"))
        XCTAssertThrowsError(try Settings.normalizedURL("example.invalid"))
    }
}
private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating:0,count:4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer,maxLength:buffer.count)
        if count <= 0 { break }; data.append(buffer,count:count)
    }
    return data
}
final class MapLayoutTests: XCTestCase {
    func testIPadLandscapeReservesLeftWorkspaceAndPortraitUsesBottomPanel() {
        let landscape = MapLayout(width: 1133, height: 744, regularWidth: true, expanded: true)
        XCTAssertTrue(landscape.usesSidebar)
        XCTAssertLessThan(landscape.sidebarWidth, landscape.width / 2)
        XCTAssertGreaterThan(landscape.insets.left, landscape.sidebarWidth)
        XCTAssertLessThan(landscape.insets.bottom, 100)
        let collapsed = MapLayout(width: 1133, height: 744, regularWidth: true, expanded: false)
        XCTAssertLessThan(collapsed.insets.left, 100)
        let portrait = MapLayout(width: 744, height: 1133, regularWidth: true, expanded: true)
        XCTAssertFalse(portrait.usesSidebar)
        XCTAssertGreaterThan(portrait.insets.bottom, 300)
    }
    func testPhoneLandscapeAndNarrowMultitaskingAvoidSidebar() {
        XCTAssertFalse(MapLayout(width: 852, height: 393, regularWidth: false, expanded: true).usesSidebar)
        XCTAssertFalse(MapLayout(width: 600, height: 500, regularWidth: true, expanded: true).usesSidebar)
    }
}

final class AppConfigurationTests: XCTestCase {
    func testBundledMapCredentialAndMissingBuildVariable() {
        XCTAssertEqual(AppConfiguration.amapKey(in: ["AMapIOSKey": " test-ios-key "]), "test-ios-key")
        XCTAssertEqual(AppConfiguration.amapKey(in: [:]), "")
        XCTAssertEqual(AppConfiguration.amapKey(in: ["AMapIOSKey": "$(AMAP_IOS_KEY)"]), "")
    }
}
final class ItineraryDetentTests: XCTestCase {
    func testDragDownClosesAndDragUpOpens() {
        let h = 780.0
        XCTAssertEqual(ItineraryDetent.settle(from: .half, translation: 280, projected: 300, availableHeight: h), .compact)
        XCTAssertEqual(ItineraryDetent.settle(from: .compact, translation: -260, projected: -270, availableHeight: h), .half)
        XCTAssertEqual(ItineraryDetent.settle(from: .half, translation: -300, projected: -320, availableHeight: h), .full)
        XCTAssertEqual(ItineraryDetent.settle(from: .full, translation: 270, projected: 280, availableHeight: h), .half)
    }
    func testSmallDragAndFlickHavePredictableStops() {
        XCTAssertEqual(ItineraryDetent.settle(from: .half, translation: 8, projected: 12, availableHeight: 780), .half)
        XCTAssertEqual(ItineraryDetent.settle(from: .half, translation: 100, projected: 640, availableHeight: 780), .compact)
        XCTAssertEqual(ItineraryDetent.full.height(in: 780), 780)
    }
}

final class RoutePolicyTests: XCTestCase {
    @MainActor func testAutomaticModeAtTwoKilometreBoundaryAndCacheReuse() {
        let start = Coordinate(latitude: 0, longitude: 0)
        func point(_ metres: Double) -> Coordinate {
            Coordinate(latitude: metres / 6_371_000 * 180 / .pi, longitude: 0)
        }
        XCTAssertEqual(TravelMode.auto.resolved(from: start, to: point(1999.999)), .walking)
        XCTAssertEqual(TravelMode.auto.resolved(from: start, to: point(2000)), .driving)
        XCTAssertEqual(TravelMode.auto.resolved(from: start, to: point(2001)), .driving)
        XCTAssertEqual(RouteCache.key(start, point(1000), mode: .auto), RouteCache.key(start, point(1000), mode: .walking))
        XCTAssertEqual(RouteCache.key(start, point(3000), mode: .auto), RouteCache.key(start, point(3000), mode: .driving))
    }
    @MainActor func testTerminalFallbackDecodesNullMetricsAndSurvivesDiskCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for fallback in ["OVER_DIRECTION_RANGE", "UNSUPPORTED_REGION"] {
            let payload = "{\"path\":[{\"lat\":31,\"lng\":121},{\"lat\":35,\"lng\":139}],\"distance\":null,\"duration\":null,\"fallback\":\"\(fallback)\"}"
            let route = try JSONDecoder().decode(PlannedRoute.self, from: Data(payload.utf8))
            XCTAssertTrue(route.isFallback); XCTAssertNil(route.distance); XCTAssertNil(route.duration)
            RouteCache(directory: directory).put(route, key: fallback)
            let reloaded = RouteCache(directory: directory).get(fallback)
            XCTAssertEqual(reloaded?.fallback, fallback)
            XCTAssertEqual(reloaded?.path.count, 2)
        }
    }
}

private struct PlaceLookupMock: MapServices {
    var fails = false
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] { [] }
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TravelMode) async throws -> PlannedRoute { throw AppError.message("unused") }
    func details(at coordinate: Coordinate) async throws -> Place {
        try await Task.sleep(for: .milliseconds(10))
        if fails { throw AppError.message("mock failure") }
        return Place(id: "lookup", name: "地点\(coordinate.latitude)", address: "查询地址", coordinates: Coordinate(latitude: 30, longitude: 120))
    }
}
final class LongPressLookupTests: XCTestCase {
    @MainActor func testLookupPopulatesNameAndAddressWithoutMovingPinOrUpdatingStaleDraft() async throws {
        let store = AppStore(settings: Settings(), demo: false, services: PlaceLookupMock())
        store.create(at: Coordinate(latitude: 31, longitude: 121))
        let oldID = store.draft?.id
        let chosen = Coordinate(latitude: 32, longitude: 122)
        store.create(at: chosen)
        XCTAssertNotEqual(store.draft?.id, oldID)
        XCTAssertTrue(store.draft?.resolvingPlace == true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.draft?.title, "地点32.0")
        XCTAssertEqual(store.draft?.address, "查询地址")
        XCTAssertEqual(store.draft?.coordinates, chosen)
        XCTAssertFalse(store.draft?.resolvingPlace ?? true)
    }
    @MainActor func testLookupFailureKeepsEditableDraft() async throws {
        let store = AppStore(settings: Settings(), demo: false, services: PlaceLookupMock(fails: true))
        store.create(at: Coordinate(latitude: 31, longitude: 121))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(store.draft?.placeLookupFailed == true)
        XCTAssertFalse(store.draft?.resolvingPlace ?? true)
        XCTAssertEqual(store.draft?.title, "")
        XCTAssertNotNil(store.draft)
    }
}
