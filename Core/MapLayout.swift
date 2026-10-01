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
    var usesSidebar: Bool { regularWidth && width >= 700 }
    var sidebarWidth: Double { min(360, max(320, width * 0.30)) }
    var listHeight: Double { min(240, height * 0.31) }
    var insets: MapViewportInsets {
        if usesSidebar {
            return MapViewportInsets(top: 50, left: expanded ? sidebarWidth + 56 : 80, bottom: 70, right: 55)
        }
        return MapViewportInsets(top: 85, left: 35, bottom: sheetHeight.map { $0 + 25 } ?? (expanded ? min(390, height * 0.48) : 125), right: 35)
    }
}

// Selection and settling belong to the native sheet presentation controller.
enum ItineraryDetent: Equatable {
    case compact, half, full
}
