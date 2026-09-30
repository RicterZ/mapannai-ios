import Foundation

struct MapViewportInsets: Equatable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
    static let phone = MapViewportInsets(top: 180, left: 35, bottom: 350, right: 35)
}
struct MapLayout: Equatable {
    var width: Double
    var height: Double
    var regularWidth: Bool
    var expanded: Bool
    var sheetHeight: Double? = nil
    var usesSidebar: Bool { regularWidth && width >= 760 && width > height }
    var sidebarWidth: Double { min(360, max(320, width * 0.30)) }
    var listHeight: Double { min(240, height * 0.31) }
    var insets: MapViewportInsets {
        if usesSidebar {
            return MapViewportInsets(top: 50, left: expanded ? sidebarWidth + 56 : 80, bottom: 70, right: 55)
        }
        return MapViewportInsets(top: 85, left: 35, bottom: sheetHeight.map { $0 + 25 } ?? (expanded ? min(390, height * 0.48) : 125), right: 35)
    }
}

// Three stable stops; settle using projected drag so quick flicks work in both directions.
enum ItineraryDetent: Int, CaseIterable {
    case compact, half, full
    func height(in availableHeight: Double) -> Double {
        switch self {
        case .compact: 60
        case .half: max(260, min(380, availableHeight * 0.48))
        case .full: max(300, availableHeight)
        }
    }
    static func settle(from current: ItineraryDetent, translation: Double, projected: Double, availableHeight: Double) -> ItineraryDetent {
        let target = current.height(in: availableHeight) - translation - (projected-translation)*0.35
        return allCases.min { abs($0.height(in: availableHeight)-target) < abs($1.height(in: availableHeight)-target) } ?? current
    }
}
