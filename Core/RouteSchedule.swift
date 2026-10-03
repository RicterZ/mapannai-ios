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
