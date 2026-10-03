import Foundation

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case walking, cycling, driving, taxi, bus, subway, train, flight, ferry, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .walking: "步行"; case .cycling: "骑行"; case .driving: "驾车"; case .taxi: "出租车"
        case .bus: "公交"; case .subway: "地铁"; case .train: "火车"; case .flight: "飞机"; case .ferry: "轮船"; case .other: "其他"
        }
    }
    var symbol: String {
        switch self {
        case .walking: "figure.walk"; case .cycling: "bicycle"; case .driving: "car"; case .taxi: "car.side"
        case .bus: "bus"; case .subway: "tram"; case .train: "train.side.front.car"; case .flight: "airplane"; case .ferry: "ferry"; case .other: "arrow.triangle.branch"
        }
    }
}
struct ChainStop: Codable, Hashable, Identifiable {
    var id: String
    var markerId: String
    var startTime: String? = nil
    var durationMinutes: Int? = nil
    var note: String? = nil
    var summary: String { RouteScheduleText.summary(time: startTime, duration: durationMinutes) }
}
struct ChainLeg: Codable, Hashable {
    var fromStopId: String
    var toStopId: String
    var mode: TransportMode
    var serviceNumber: String? = nil
    var startTime: String? = nil
    var durationMinutes: Int? = nil
    var note: String? = nil
    var summary: String { RouteScheduleText.summary(time: startTime, duration: durationMinutes) }
}
struct RouteChain: Codable, Hashable, Identifiable {
    var id: String
    var stops: [ChainStop]
    var legs: [ChainLeg]
    var inactiveLegs: [ChainLeg]? = nil
    /// Visit identity and its schedule stay in this route. A new member gets a new visit.
    func reordered(to markerIDs: [String]) -> RouteChain {
        var copy = self
        copy.stops = markerIDs.map { markerID in
            stops.first { $0.markerId == markerID } ?? ChainStop(id: "stop_" + UUID().uuidString, markerId: markerID)
        }
        let visits = Set(copy.stops.map(\.id))
        let pairs = Set(zip(copy.stops, copy.stops.dropFirst()).map { DirectedVisitPair(from: $0.id, to: $1.id) })
        let edges = (legs + (inactiveLegs ?? [])).filter { visits.contains($0.fromStopId) && visits.contains($0.toStopId) }
        copy.legs = edges.filter { pairs.contains(DirectedVisitPair(from: $0.fromStopId, to: $0.toStopId)) }
        let disconnected = edges.filter { !pairs.contains(DirectedVisitPair(from: $0.fromStopId, to: $0.toStopId)) }
        copy.inactiveLegs = disconnected.isEmpty ? nil : disconnected
        return copy
    }
    var hasSchedule: Bool {
        !legs.isEmpty || !(inactiveLegs ?? []).isEmpty || stops.contains { $0.startTime != nil || $0.durationMinutes != nil || $0.note != nil }
    }
    func leg(at position: Int) -> ChainLeg? {
        guard stops.indices.contains(position), stops.indices.contains(position + 1) else { return nil }
        return legs.first { $0.fromStopId == stops[position].id && $0.toStopId == stops[position + 1].id }
    }
}
enum RouteScheduleText {
    static func duration(_ minutes: Int) -> String {
        if minutes > 0 && minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }
    static func summary(time: String?, duration: Int?) -> String {
        [time, duration.map(Self.duration)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
struct RouteScheduleRequest: Identifiable {
    var id = UUID()
    let day: TripDay
    let route: RouteChain
    let position: Int
    let isTransport: Bool
    let fromTitle: String
    let toTitle: String?
}

private struct DirectedVisitPair: Hashable { let from: String; let to: String }

extension TripDay {
    /// Mutate by original route slot, then remove empty routes. Never infer identity from overlap locally.
    mutating func setRouteOrders(_ orders: [[String]]) {
        let previousChains = chains
        if let routes = routeChains, routes.count == previousChains.count,
           zip(routes, previousChains).allSatisfy({ $0.stops.map(\.markerId) == $1 }) {
            routeChains = orders.enumerated().compactMap { index, ids in
                guard !ids.isEmpty else { return nil }
                if routes.indices.contains(index) { return routes[index].reordered(to: ids) }
                return RouteChain(id: "chain_" + UUID().uuidString, stops: ids.map { ChainStop(id: "stop_" + UUID().uuidString, markerId: $0) }, legs: [])
            }
        }
        chains = orders.filter { !$0.isEmpty }
    }
    mutating func removeRoute(at index: Int) {
        guard chains.indices.contains(index) else { return }
        if let routes = routeChains, routes.count == chains.count { routeChains?.remove(at: index) }
        chains.remove(at: index)
    }
}

/// Select an existing atomic endpoint. The legacy multi-route endpoint may infer
/// identities by overlap; reject a write if that inference would move schedules.
struct RouteOrderWrite {
    let path: String
    let method: String
    let body: [String: Any]
    init(previous: TripDay, updated: TripDay) throws {
        let base = "trips/" + APIClient.id(previous.tripId) + "/days/" + APIClient.id(previous.id)
        if let old = previous.routeChains, let new = updated.routeChains, old.map(\.id) == new.map(\.id) {
            let changed = old.indices.filter { old[$0].stops.map(\.markerId) != new[$0].stops.map(\.markerId) }
            if changed.count == 1, let index = changed.first, new[index].stops.count >= 2 {
                path = base + "/chains/" + APIClient.id(old[index].id)
                method = "PATCH"; body = ["markerIds": new[index].stops.map(\.markerId)]; return
            }
        }
        if let old = previous.routeChains, let new = updated.routeChains, previous.chains != updated.chains {
            var used = Set<String>()
            var matches = updated.chains.map { ids -> RouteChain? in
                guard let route = old.first(where: { !used.contains($0.id) && $0.stops.map(\.markerId) == ids }) else { return nil }
                used.insert(route.id); return route
            }
            for index in updated.chains.indices {
                if matches[index] == nil {
                    let candidates = old.filter { !used.contains($0.id) }
                    let best = candidates.map { route in route.stops.filter { updated.chains[index].contains($0.markerId) }.count }.max() ?? 0
                    let winners = candidates.filter { route in best > 0 && route.stops.filter { updated.chains[index].contains($0.markerId) }.count == best }
                    if winners.count == 1 { matches[index] = winners[0]; used.insert(winners[0].id) }
                    else if winners.contains(where: \.hasSchedule) { throw AppError.message("当前服务无法明确这次移动的安排归属，请先调整路线后重试") }
                }
                let intended = new[index]
                let inferred = matches[index]
                if inferred?.id != intended.id && (intended.hasSchedule || inferred?.hasSchedule == true || old.contains { $0.id == intended.id && $0.hasSchedule }) {
                    throw AppError.message("当前服务无法保留这次跨路线移动的安排归属，请先调整路线后重试")
                }
            }
        }
        path = base; method = "PUT"
        body = ["title": updated.title ?? "", "emoji": updated.emoji ?? "", "markerIds": updated.markerIds, "chains": updated.chains]
    }
}
