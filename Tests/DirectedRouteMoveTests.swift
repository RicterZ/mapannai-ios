import XCTest
@testable import MapAnNai

final class DirectedRouteMoveTests: XCTestCase {
    private func route(_ id: String, _ markers: [String]) -> RouteChain {
        let stops = markers.map { ChainStop(id: id + "-" + $0, markerId: $0, startTime: "09:30", durationMinutes: 20, note: "访问" + $0) }
        let legs = zip(stops, stops.dropFirst()).map { ChainLeg(fromStopId: $0.id, toStopId: $1.id, mode: .subway, serviceNumber: $0.markerId + "→" + $1.markerId) }
        return RouteChain(id: id, stops: stops, legs: legs)
    }
    private func day(_ routes: [RouteChain]) -> TripDay {
        TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: Array(Set(routes.flatMap { $0.stops.map(\.markerId) })), chains: routes.map { $0.stops.map(\.markerId) }, routeChains: routes)
    }
    func testReorderDisconnectsAndRestoresOnlyOriginalDirectedEdges() throws {
        let original = route("r", ["a", "b", "c"])
        let moved = original.reordered(to: ["a", "c", "b"])
        XCTAssertTrue(moved.legs.isEmpty)
        XCTAssertEqual(moved.inactiveLegs?.count, 2)
        XCTAssertEqual(moved.stops.map(\.id), ["r-a", "r-c", "r-b"])
        XCTAssertEqual(moved.stops[2].note, "访问b")
        XCTAssertNil(moved.leg(at: 1)) // C→B must never reuse B→C.
        XCTAssertEqual(moved.reordered(to: ["a", "b", "c"]), original)
        let decoded = try JSONDecoder().decode(RouteChain.self, from: JSONEncoder().encode(moved))
        XCTAssertEqual(decoded.reordered(to: ["a", "b", "c"]), original)
    }
    func testUnaffectedAdjacentEdgesStayActiveAndTimesAreNotRescheduled() {
        let original = route("r", ["a", "b", "c", "d"])
        let moved = original.reordered(to: ["c", "d", "a", "b"])
        XCTAssertEqual(moved.legs.map(\.serviceNumber), ["a→b", "c→d"])
        XCTAssertEqual(moved.inactiveLegs?.map(\.serviceNumber), ["b→c"])
        XCTAssertTrue(moved.stops.allSatisfy { $0.startTime == "09:30" })
    }
    func testCrossRouteMoveCreatesFreshVisitAndRemovesIncidentEdges() throws {
        var original = day([route("first", ["a", "b", "c"]), route("second", ["d", "e"])])
        let previous = original
        original.setRouteOrders([["a", "c"], ["d", "b", "e"]])
        let routes = try XCTUnwrap(original.routeChains)
        XCTAssertEqual(routes.map(\.id), ["first", "second"])
        XCTAssertEqual(routes[0].stops.map(\.id), ["first-a", "first-c"])
        XCTAssertTrue(routes[0].legs.isEmpty)
        XCTAssertNil(routes[0].inactiveLegs)
        XCTAssertEqual(routes[1].inactiveLegs?.map(\.serviceNumber), ["d→e"])
        let visit = try XCTUnwrap(routes[1].stops.first { $0.markerId == "b" })
        XCTAssertNotEqual(visit.id, "first-b")
        XCTAssertNil(visit.startTime); XCTAssertNil(visit.note)
        XCTAssertEqual(original.markerIds, previous.markerIds)
        XCTAssertEqual(try RouteOrderWrite(previous: previous, updated: original).method, "PUT")
    }
    func testPoolRemovalDeletesVisitEvenWhenReaddedToSameRoute() throws {
        var value = day([route("r", ["a", "b", "c"])])
        value.setRouteOrders([["a", "c"]])
        XCTAssertTrue(value.markerIds.contains("b"))
        XCTAssertNil(value.routeChains?[0].inactiveLegs)
        value.setRouteOrders([["a", "b", "c"]])
        let visit = try XCTUnwrap(value.routeChains?[0].stops[1])
        XCTAssertNotEqual(visit.id, "r-b"); XCTAssertNil(visit.startTime)
        XCTAssertTrue(value.routeChains?[0].legs.isEmpty == true)
    }
    func testEmptySourceDoesNotStealTargetRouteIdentity() throws {
        var value = day([route("first", ["a"]), route("second", ["b", "c"])])
        value.setRouteOrders([[], ["b", "a", "c"]])
        XCTAssertEqual(value.routeChains?.map(\.id), ["second"])
        XCTAssertEqual(value.routeChains?.first?.stops.first?.id, "second-b")
        XCTAssertEqual(value.chains, [["b", "a", "c"]])
        XCTAssertNil(value.routeChains?.first?.stops[1].startTime)
    }
    func testSameRouteUsesStableIDPatchAndNoMetadataOverwrite() throws {
        let previous = day([route("r", ["a", "b", "c"])])
        var updated = previous; updated.setRouteOrders([["c", "b", "a"]])
        let write = try RouteOrderWrite(previous: previous, updated: updated)
        XCTAssertEqual(write.path, "trips/trip/days/day/chains/r")
        XCTAssertEqual(write.method, "PATCH")
        XCTAssertEqual(write.body["markerIds"] as? [String], ["c", "b", "a"])
        XCTAssertNil(write.body["legs"]); XCTAssertNil(write.body["routeChains"])
    }
    func testAmbiguousLegacyCrossRouteCannotSilentlyReassignSchedules() {
        let previous = day([route("first", ["a", "b"]), route("second", ["b", "c"])])
        var updated = previous; updated.setRouteOrders([["b"], ["b", "a", "c"]])
        XCTAssertThrowsError(try RouteOrderWrite(previous: previous, updated: updated))
    }
    func testDeletePlaceAndEditRouteCleanActiveAndInactiveEdgesTogether() throws {
        var value = day([route("r", ["a", "b", "c"]), route("other", ["d", "e"])])
        value.setRouteOrders([["a", "c", "b"], ["d", "e"]])
        let removed = value.removing("b")
        XCTAssertNil(removed.routeChains?[0].inactiveLegs)
        XCTAssertEqual(removed.routeChains?[1], value.routeChains?[1])
        let edit = try RouteEditSession(day: value, index: 0, ids: ["a", "b", "c"]).applying(to: value)
        XCTAssertEqual(edit.routeChains?[0].legs.count, 2)
        let deleted = try RouteEditSession(day: value, index: 0, ids: []).applying(to: value)
        XCTAssertEqual(deleted.routeChains?.map(\.id), ["other"])
    }
}
