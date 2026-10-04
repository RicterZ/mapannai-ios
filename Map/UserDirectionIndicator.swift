import UIKit
import CoreLocation

/// Shared heading sensor and direction fan; map adapters only project the user position.
@MainActor final class UserDirectionIndicator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private weak var host: UIView?
    private let fan = CAShapeLayer()
    private var project: (() -> CGPoint?)?
    private var bearing: (() -> Double)?
    var onHeading: ((Double) -> Void)?
    private(set) var heading: Double?
    override init() {
        super.init(); manager.delegate = self
        let path = UIBezierPath(); path.move(to: .zero)
        path.addArc(withCenter: .zero, radius: 30, startAngle: -.pi / 2 - .pi / 7, endAngle: -.pi / 2 + .pi / 7, clockwise: true)
        path.close(); fan.path = path.cgPath
        fan.fillColor = UIColor.systemBlue.withAlphaComponent(0.22).cgColor
        fan.strokeColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor; fan.lineWidth = 0.7
        fan.zPosition = 900; fan.isHidden = true
    }
    func attach(to view: UIView, project: @escaping () -> CGPoint?, bearing: @escaping () -> Double) {
        if host !== view { fan.removeFromSuperlayer(); host = view; view.layer.addSublayer(fan) }
        self.project = project; self.bearing = bearing
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        refresh()
    }
    func refresh() {
        guard let heading, let point = project?(), point.x.isFinite, point.y.isFinite else { fan.isHidden = true; return }
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
