import XCTest
@testable import MapAnNai

final class SearchSelectionTests: XCTestCase {
    @MainActor func testSelectionKeepsSearchAndRepeatedMapTapExpandsSameDraft() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let place = Place(id: "result", name: "测试", address: "地址", coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        store.searchText = "测试"; store.searchResults = [place]
        store.choose(place)
        XCTAssertEqual(store.searchText, "测试"); XCTAssertEqual(store.searchResults, [place])
        XCTAssertFalse(store.draftExpanded)
        let draftID = try XCTUnwrap(store.draft?.id)
        store.draft?.title = "我输入的名称"
        let cameraID = store.camera?.id
        store.choose(place, fromMap: true)
        XCTAssertTrue(store.draftExpanded)
        XCTAssertEqual(store.draft?.id, draftID)
        XCTAssertEqual(store.draft?.title, "我输入的名称")
        XCTAssertEqual(store.camera?.id, cameraID)
        store.draft = nil
        store.choose(place, fromMap: true)
        XCTAssertFalse(store.draftExpanded)
        XCTAssertNotEqual(store.draft?.id, draftID)
        store.clearSearch()
        XCTAssertTrue(store.searchResults.isEmpty); XCTAssertNil(store.selectedSearchPlaceID)
    }
    @MainActor func testNearbySavedPlacesUseThirtyKilometreRadiusAndClearRestoresThem() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        store.bounds = SearchBounds(west: 121.4, south: 31.18, east: 121.48, north: 31.24)
        let far = Marker(id: "far", coordinates: Coordinate(latitude: 32.5, longitude: 121.44),
                         content: MarkerContent(id: "far", title: "远方", iconType: .location, markdownContent: ""))
        store.markers.append(far)
        let day = try XCTUnwrap(store.day)
        store.beginAddingPlace(to: day)
        XCTAssertEqual(store.searchResults.count, 5)
        XCTAssertTrue(store.searchResults.allSatisfy { $0.markerId != "far" })
        let first = try XCTUnwrap(store.searchResults.first)
        store.choose(first, fromMap: true)
        XCTAssertEqual(store.searchDetailPlace?.id, first.id)
        XCTAssertNil(store.draft)
        store.searchDetailPlace = nil
        store.searchText = "静安"
        await store.search()
        XCTAssertEqual(store.searchResults.count, 1)
        store.clearSearch()
        XCTAssertEqual(store.searchResults.count, 5)
        XCTAssertEqual(store.addPlaceDay?.id, day.id)
    }
    @MainActor func testDemoSearchShowsAllMatchingReadOnlyPlaces() async {
        let store = AppStore(settings: Settings(), demo: true)
        let cameraID = store.camera?.id
        store.searchText = "武康"
        await store.search()
        XCTAssertEqual(store.searchResults.map(\.name), ["武康大楼", "武康庭"])
        XCTAssertEqual(store.camera?.id, cameraID)
        XCTAssertEqual(store.searchText, "武康")
    }
    @MainActor func testDayAddSearchSharesMapResultsAndKeepsTargetDay() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        let day = try XCTUnwrap(store.day)
        store.beginAddingPlace(to: day)
        XCTAssertEqual(store.addPlaceDay?.id, day.id)
        store.searchText = "静安"
        await store.search()
        let result = try XCTUnwrap(store.searchResults.first)
        store.choose(result)
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.selectedSearchPlace?.name, "静安寺")
        let camera = store.camera?.id
        XCTAssertFalse(store.isPlaceAdded(result))
        store.choose(result, fromMap: true)
        XCTAssertEqual(store.camera?.id, camera)
        XCTAssertNil(store.draft)
        store.choose(result, fromMap: true)
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.addPlaceDay?.id, day.id)
        XCTAssertEqual(store.searchText, "静安")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.searchDetailPlace?.id, result.id)
        XCTAssertFalse(store.isPlaceAdded(result))
        XCTAssertEqual(store.trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id })?.markerIds, day.markerIds)
        store.endAddingPlace()
        XCTAssertNil(store.addPlaceDay); XCTAssertNil(store.draft)
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    @MainActor func testSavedResultFromOverviewShowsDetailsWithoutDraft() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        let marker = try XCTUnwrap(store.markers.first)
        store.beginAddingPlace()
        let place = Place(id: "marker:\(marker.id)", name: marker.title, address: "",
                          coordinates: marker.coordinates, markerId: marker.id)
        await store.activateSavedSearchPlace(place)
        XCTAssertFalse(store.placeSearchPresented)
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.selectedMarker?.id, marker.id)
    }

    @MainActor func testPartialSaveRetriesMembershipWithoutCreatingAgainAndKeepsTarget() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let client = APIClient(baseURL: "https://add-flow.invalid", token: "", session: session)
        let store = AppStore(settings: Settings(), demo: true)
        let target = try XCTUnwrap(store.day)
        store.beginAddingPlace(to: target)
        let place = Place(id: "new-poi", name: "新地点", address: "地址", coordinates: Coordinate(latitude: 30, longitude: 120))
        store.searchText = "新地点"; store.searchResults = [place]
        let targetPath = ("/api/" + AppStore.dayPath(target)).removingPercentEncoding!
        var creates = 0, joins = 0
        MockURLProtocol.handler = { request in
            if request.url!.path == "/api/markers" {
                XCTAssertEqual(request.httpMethod, "POST")
                creates += 1
                let marker = Marker(id: "new-id", coordinates: place.coordinates, content: MarkerContent(id: "new-id", title: place.name, markdownContent: ""))
                return (200, try JSONEncoder().encode(marker))
            }
            XCTAssertEqual(request.url!.path, targetPath)
            joins += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            return joins == 1 ? (500, Data("{}".utf8)) : (200, try JSONEncoder().encode(target.addingToDefaultRoute(["new-id"])))
        }
        let first = await store.addSearchPlace(place, using: client)
        XCTAssertFalse(first); XCTAssertNotNil(store.addPlaceError)
        store.select(trip: store.trip, day: store.trip?.days.last, focus: false)
        let second = await store.addSearchPlace(place, using: client)
        XCTAssertTrue(second)
        XCTAssertEqual(creates, 1); XCTAssertEqual(joins, 2)
        XCTAssertEqual(store.addPlaceDay?.id, target.id)
        XCTAssertEqual(store.searchText, "新地点"); XCTAssertEqual(store.searchResults, [place])
        XCTAssertTrue(store.isPlaceAdded(place))
        let third = await store.addSearchPlace(place, using: client)
        XCTAssertTrue(third); XCTAssertEqual(joins, 2)
    }
    @MainActor func testContinuousAddReusesSavedPlaceAndAppendsDefaultRouteKeepingSearch() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let client = APIClient(baseURL: "https://add-flow.invalid", token: "", session: session)
        let store = AppStore(settings: Settings(), demo: true)
        let target = try XCTUnwrap(store.day)
        let existing = try XCTUnwrap(store.markers.first { !target.markerIds.contains($0.id) })
        let savedPlace = Place(id: "provider-id", name: existing.title, address: "", coordinates: existing.coordinates)
        let newPlace = Place(id: "another-poi", name: "另一地点", address: "", coordinates: Coordinate(latitude: 30, longitude: 120))
        store.beginAddingPlace(to: target)
        store.searchText = "地点"; store.searchResults = [savedPlace, newPlace]
        var creates = 0, joins = 0
        MockURLProtocol.handler = { request in
            if request.url!.path == "/api/markers" {
                creates += 1
                let marker = Marker(id: "another-id", coordinates: newPlace.coordinates, content: MarkerContent(id: "another-id", title: newPlace.name, markdownContent: ""))
                return (200, try JSONEncoder().encode(marker))
            }
            joins += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            var confirmed = target
            confirmed.markerIds = body["markerIds"] as! [String]
            confirmed.chains = body["chains"] as! [[String]]
            return (200, try JSONEncoder().encode(confirmed))
        }
        let first = await store.addSearchPlace(savedPlace, using: client)
        let second = await store.addSearchPlace(newPlace, using: client)
        XCTAssertTrue(first); XCTAssertTrue(second)
        XCTAssertEqual(creates, 1); XCTAssertEqual(joins, 2)
        XCTAssertTrue(store.isPlaceAdded(savedPlace)); XCTAssertTrue(store.isPlaceAdded(newPlace))
        XCTAssertEqual(store.searchResults, [savedPlace, newPlace]); XCTAssertEqual(store.searchText, "地点")
        XCTAssertEqual(store.day?.chains, [target.chains[0] + [existing.id, "another-id"]])
        XCTAssertEqual(store.day?.markerIds.count, target.markerIds.count + 2)
        XCTAssertNotNil(store.addPlaceDay)
    }

    @MainActor func testGeneralSearchSavesWithoutAddingToSelectedDay() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let client = APIClient(baseURL: "https://search.invalid", token: "", session: session)
        let store = AppStore(settings: Settings(), demo: true)
        let trips = store.trips
        store.beginAddingPlace()
        XCTAssertTrue(store.placeSearchPresented); XCTAssertNil(store.addPlaceDay)
        let place = Place(id: "general", name: "独立地点", address: "", coordinates: Coordinate(latitude: 30, longitude: 120))
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url!.path, "/api/markers")
            XCTAssertEqual(request.httpMethod, "POST")
            let marker = Marker(id: "general", coordinates: place.coordinates, content: MarkerContent(id: "general", title: place.name, markdownContent: ""))
            return (200, try JSONEncoder().encode(marker))
        }
        let saved = await store.addSearchPlace(place, using: client)
        XCTAssertTrue(saved); XCTAssertEqual(store.trips, trips)
        XCTAssertTrue(store.isPlaceAdded(place))
        store.endAddingPlace(); XCTAssertFalse(store.placeSearchPresented)
    }

    @MainActor func testTripSearchFreezesMembershipAndRetriesWithoutDuplicateCreation() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel(); MockURLProtocol.handler = nil }
        let client = APIClient(baseURL: "https://trip-search.invalid", token: "", session: session)
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        let chains = trip.days.map(\.chains)
        store.beginAddingPlace(tripID: trip.id)
        let place = Place(id: "trip-poi", name: "旅行收藏", address: "", coordinates: Coordinate(latitude: 30, longitude: 120))
        var creates = 0, joins = 0
        MockURLProtocol.handler = { request in
            if request.url!.path == "/api/markers" {
                creates += 1
                return (200, try JSONEncoder().encode(Marker(id: "trip-place", coordinates: place.coordinates,
                    content: MarkerContent(id: "trip-place", title: place.name, markdownContent: ""))))
            }
            XCTAssertEqual(request.url!.path, "/api/trips/" + trip.id + "/markers")
            XCTAssertEqual(request.httpMethod, "POST")
            joins += 1
            return (joins == 1 ? 500 : 200, Data("{}".utf8))
        }
        let first = await store.addSearchPlace(place, using: client)
        XCTAssertFalse(first)
        store.select(trip: nil, focus: false)
        let second = await store.addSearchPlace(place, using: client)
        XCTAssertTrue(second)
        XCTAssertEqual(creates, 1); XCTAssertEqual(joins, 2)
        XCTAssertEqual(store.trips.first?.markerIds, ["trip-place"])
        XCTAssertEqual(store.trips.first?.days.map(\.chains), chains)
        XCTAssertTrue(store.isPlaceAdded(place))
    }
    func testOldTripPayloadWithoutMembershipDecodes() throws {
        let trip = try JSONDecoder().decode(Trip.self, from: Data(#"{"id":"t","name":"Trip","startDate":"2026-10-01","endDate":"2026-10-01","days":[]}"#.utf8))
        XCTAssertNil(trip.markerIds)
    }

}
