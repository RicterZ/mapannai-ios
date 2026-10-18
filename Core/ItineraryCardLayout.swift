import Foundation
import JavaScriptCore

struct ItineraryLayoutAnchor: Codable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
struct ItineraryLayoutPlacement: Codable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var left: Double
    var top: Double
    var end: ItineraryLayoutPoint
}
struct ItineraryLayoutPoint: Codable {
    var x: Double
    var y: Double
}
struct ItineraryLayoutBounds: Codable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
}

/// Runs the compiled Web source unchanged; there is no second native layout solver.
actor ItineraryCardLayout {
    func layout(anchors: [ItineraryLayoutAnchor], bounds: ItineraryLayoutBounds,
                paths: [[ItineraryLayoutPoint]], previous: [ItineraryLayoutPlacement]) throws -> [ItineraryLayoutPlacement] {
        try Task.checkCancellation()
        guard let url = Bundle.main.url(forResource: "itinerary-card-layout", withExtension: "js"),
              let context = JSContext() else { throw AppError.message("缺少导览布局资源") }
        let source = try String(contentsOf: url, encoding: .utf8)
        context.evaluateScript(source)
        func object<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }
        context.setObject(try object(anchors), forKeyedSubscript: "anchors" as NSString)
        context.setObject(try object(bounds), forKeyedSubscript: "bounds" as NSString)
        context.setObject(try object(paths), forKeyedSubscript: "paths" as NSString)
        context.setObject(try object(previous), forKeyedSubscript: "previous" as NSString)
        let value = context.evaluateScript("JSON.stringify(ItineraryLayout.layoutItineraryCards(anchors,bounds,paths,previous).map(p => ({...p,end:ItineraryLayout.itineraryLeaderEnd(p)})))")
        guard context.exception == nil, let json = value?.toString(), let data = json.data(using: .utf8) else {
            throw AppError.message("导览布局计算失败")
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode([ItineraryLayoutPlacement].self, from: data)
    }
}
