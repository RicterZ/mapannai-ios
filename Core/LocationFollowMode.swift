import Foundation

enum LocationFollowMode: Equatable {
    case idle, centered, heading
    var next: Self { switch self { case .idle: .centered; case .centered: .heading; case .heading: .centered } }
    var symbol: String { self == .heading ? "location.fill" : "location" }
}

/// Keeps the entire multi-touch sequence out of the single-finger pan path.
struct LocationGesturePolicy {
    enum Event: Equatable { case none, pan, transformEnded }
    private var multiTouch = false
    private var reportedPan = false
    mutating func update(active: Bool, transform: Bool, singlePanDistance: Double?) -> Event {
        guard active else {
            let ended = multiTouch
            multiTouch = false; reportedPan = false
            return ended ? .transformEnded : .none
        }
        if transform { multiTouch = true }
        guard !multiTouch, !reportedPan, let singlePanDistance, singlePanDistance >= 8 else { return .none }
        reportedPan = true; return .pan
    }
}
