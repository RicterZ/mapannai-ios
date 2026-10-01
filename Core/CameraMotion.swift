import Foundation

/// A more relaxed counterpart to Web's 600–1000ms distance-based flyTo.
/// The renderer keeps its native interpolation; this policy only controls time.
enum CameraMotion {
    static func duration(from origin: Coordinate, to destination: Coordinate,
                         currentZoom: Double, targetZoom: Double?, fitting: Bool = false,
                         reduceMotion: Bool) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        let distance = origin.isValid && destination.isValid ? Coordinates.distance(origin, destination) : 0
        let distanceProgress = min(1, max(0, (distance - 10_000) / 190_000))
        let zoomChange = currentZoom.isFinite && targetZoom?.isFinite == true
            ? abs((targetZoom ?? currentZoom) - currentZoom) : 0
        let zoomTime = min(0.3, zoomChange * 0.06)
        return min(1.4, max(fitting ? 0.9 : 0.7, 0.7 + distanceProgress * 0.4 + zoomTime))
    }
}
