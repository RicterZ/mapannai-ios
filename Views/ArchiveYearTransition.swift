import SwiftUI
import UIKit

struct ArchiveYearLayout: PreferenceKey, Equatable {
    var heading = CGRect.zero
    var year = CGRect.zero
    var separator = CGRect.zero
    var cards: [String: CGRect] = [:]

    static let defaultValue = ArchiveYearLayout()
    static func reduce(value: inout ArchiveYearLayout, nextValue: () -> ArchiveYearLayout) {
        let next = nextValue()
        if !next.heading.isEmpty { value.heading = next.heading }
        if !next.year.isEmpty { value.year = next.year }
        if !next.separator.isEmpty { value.separator = next.separator }
        value.cards.merge(next.cards, uniquingKeysWith: { _, new in new })
    }

    func isReady(for ids: Set<String>) -> Bool {
        !heading.isEmpty && !year.isEmpty && !separator.isEmpty &&
            ids.allSatisfy {
                guard let frame = cards[$0] else { return false }
                return abs(frame.height - 204) < 1 && abs(frame.width - year.width) < 1
            }
    }
}

struct ArchiveYearPose {
    let frame: CGRect
    let transform: CATransform3D
    let opacity: CGFloat

    init(frame: CGRect) {
        self.frame = frame
        transform = CATransform3DIdentity
        opacity = 1
    }

    init(slot: CGRect, transform: CATransform3D = CATransform3DIdentity, opacity: CGFloat = 1) {
        // An 88pt archive slot is not the card's drawing bounds.
        frame = CGRect(x: slot.minX, y: slot.minY, width: slot.width, height: 204)
        self.transform = transform
        self.opacity = opacity
    }
}

struct ArchiveYearMotion {
    struct Tile {
        let id: String
        let image: UIImage
        let targetImage: UIImage
        let source: ArchiveYearPose
        let destination: ArchiveYearPose
        let order: Double
    }
    let size: CGSize
    let tiles: [Tile]
    let heading: UIImage
    let sourceHeading: CGRect
    let destinationHeading: CGRect
    let sourceSeparator: CGRect
    let destinationSeparator: CGRect
    let returning: Bool

    static func visibleHeading(_ frame: CGRect, screenTop: CGFloat = 0) -> CGRect {
        // Stop as soon as the heading and its following gap clear the viewport top.
        let minimumY = screenTop - 24 - frame.height
        return CGRect(x: frame.minX, y: max(minimumY, frame.minY), width: frame.width, height: frame.height)
    }

    static func cardClip(heading: CGRect, size: CGSize) -> CGRect {
        // Match the live ScrollView's safe-area overflow when its heading is offscreen.
        let top = min(size.height, max(-204, heading.maxY + 24))
        return CGRect(x: 0, y: top, width: size.width, height: max(0, size.height - top))
    }
}

struct ArchiveYearTransition: UIViewRepresentable {
    let motion: ArchiveYearMotion
    let reduceMotion: Bool
    let onCompletion: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let root = UIView(frame: CGRect(origin: .zero, size: motion.size))
        root.backgroundColor = .clear
        root.isUserInteractionEnabled = false
        // The shared SwiftUI mask owns the safe-area boundary, as it does for the live list.
        root.clipsToBounds = false
        let rack = UIView()
        rack.backgroundColor = .clear
        rack.clipsToBounds = true
        let sourceClip = ArchiveYearMotion.cardClip(heading: motion.sourceHeading, size: motion.size)
        rack.frame = sourceClip
        rack.bounds = sourceClip
        root.addSubview(rack)
        var pairs: [(ArchiveYearMotion.Tile, UIView, UIImageView)] = []
        for tile in motion.tiles.sorted(by: { $0.order < $1.order }) {
            let plane = UIView(frame: CGRect(origin: .zero, size: motion.size))
            plane.layer.zPosition = CGFloat(tile.order)
            rack.addSubview(plane)
            let card = UIView(frame: tile.source.frame)
            let old = UIImageView(image: tile.image)
            old.frame = card.bounds
            card.addSubview(old)
            let new = UIImageView(image: tile.targetImage)
            new.frame = card.bounds
            new.alpha = 0
            card.addSubview(new)
            card.layer.transform = tile.source.transform
            card.alpha = tile.source.opacity
            plane.addSubview(card)
            pairs.append((tile, card, new))
        }
        let line = UIView(frame: motion.sourceSeparator)
        line.backgroundColor = .tertiaryLabel
        line.layer.cornerRadius = 1
        rack.addSubview(line)
        let heading = UIImageView(image: motion.heading)
        heading.frame = motion.sourceHeading
        root.addSubview(heading)

        let animator = UIViewPropertyAnimator(duration: reduceMotion ? 0.15 : 0.45,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.2, y: 0.75),
                controlPoint2: CGPoint(x: 0.3, y: 1)))
        if reduceMotion {
            root.alpha = 0
            rack.frame = ArchiveYearMotion.cardClip(heading: motion.destinationHeading, size: motion.size)
            rack.bounds = rack.frame
            heading.frame = motion.destinationHeading
            line.frame = motion.destinationSeparator
            for (tile, card, new) in pairs {
                card.layer.transform = tile.destination.transform
                card.center = CGPoint(x: tile.destination.frame.midX, y: tile.destination.frame.midY)
                card.alpha = tile.destination.opacity
                new.alpha = 1
            }
            animator.addAnimations { root.alpha = 1 }
        } else {
            animator.addAnimations {
                let clip = ArchiveYearMotion.cardClip(heading: motion.destinationHeading, size: motion.size)
                // Matching frame and bounds keep all children in unchanged page coordinates.
                rack.frame = clip
                rack.bounds = clip
                heading.frame = motion.destinationHeading
                line.frame = motion.destinationSeparator
                for (tile, card, new) in pairs {
                    // The card bitmap and its 204pt bounds never resize during the flight.
                    card.center = CGPoint(x: tile.destination.frame.midX, y: tile.destination.frame.midY)
                    card.layer.transform = tile.destination.transform
                    card.alpha = tile.destination.opacity
                    new.alpha = 1
                }
            }
        }
        animator.addCompletion { position in
            guard position == .end else { return }
            onCompletion()
        }
        context.coordinator.animator = animator
        return root
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard !context.coordinator.started else { return }
        context.coordinator.started = true
        context.coordinator.animator?.startAnimation()
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
    }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
        var started = false
    }
}
