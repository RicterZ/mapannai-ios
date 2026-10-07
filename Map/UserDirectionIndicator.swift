import UIKit
import CoreLocation

/// Shared heading sensor and direction fan; map adapters only project the user position.
@MainActor final class UserDirectionIndicator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private weak var host: UIView?
    private let fan = CALayer()
    private var project: (() -> CGPoint?)?
    private var bearing: (() -> Double)?
    private var annotationView: (() -> UIView?)?
    var onHeading: ((Double) -> Void)?
    private(set) var heading: Double?
    override init() {
        super.init(); manager.delegate = self
        // Radial fade matches a soft heading beam, without a hard arc or outline.
        let radius: CGFloat = 52
        let size = CGSize(width: radius * 2, height: radius * 2)
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let origin = CGPoint(x: radius, y: radius)
            let wedge = UIBezierPath(); wedge.move(to: origin)
            wedge.addArc(withCenter: origin, radius: radius, startAngle: -.pi / 2 - .pi / 7,
                         endAngle: -.pi / 2 + .pi / 7, clockwise: true)
            wedge.close(); context.addPath(wedge.cgPath); context.clip()
            let colors = [UIColor.systemBlue.withAlphaComponent(0.52).cgColor,
                          UIColor.systemBlue.withAlphaComponent(0.27).cgColor,
                          UIColor.systemBlue.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                context.drawRadialGradient(gradient, startCenter: origin, startRadius: 5,
                                           endCenter: origin, endRadius: radius, options: [])
            }
        }
        fan.bounds = CGRect(origin: .zero, size: size)
        fan.contents = image.cgImage; fan.contentsScale = image.scale
        fan.zPosition = 900; fan.isHidden = true
    }
    func attach(to view: UIView, project: @escaping () -> CGPoint?, bearing: @escaping () -> Double) {
        if host !== view { fan.removeFromSuperlayer(); host = view; view.layer.addSublayer(fan) }
        self.project = project; self.bearing = bearing
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        refresh()
    }
    func attach(toAnnotation view: @escaping () -> UIView?, bearing: @escaping () -> Double) {
        annotationView = view
        self.bearing = bearing
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        refresh()
    }
    func refresh() {
        let point: CGPoint?
        if let annotationView {
            guard let view = annotationView() else { fan.isHidden = true; return }
            if host !== view { fan.removeFromSuperlayer(); host = view; view.layer.insertSublayer(fan, at: 0) }
            point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        } else { point = project?() }
        guard let heading, let point, point.x.isFinite, point.y.isFinite else { fan.isHidden = true; return }
        if let scene = host?.window?.windowScene {
            switch scene.interfaceOrientation {
            case .landscapeLeft: manager.headingOrientation = .landscapeLeft
            case .landscapeRight: manager.headingOrientation = .landscapeRight
            case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
            default: manager.headingOrientation = .portrait
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fan.position = point; fan.setAffineTransform(CGAffineTransform(rotationAngle: (heading - (bearing?() ?? 0)) * .pi / 180))
        fan.isHidden = false; CATransaction.commit()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading value: CLHeading) {
        guard value.headingAccuracy >= 0 else { return }
        heading = value.trueHeading >= 0 ? value.trueHeading : value.magneticHeading
        onHeading?(heading!); refresh()
    }
    func stop() { manager.stopUpdatingHeading(); fan.removeFromSuperlayer(); host = nil }
}
