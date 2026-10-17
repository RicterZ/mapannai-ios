import SwiftUI
import UIKit

enum DayReorderSection: Hashable {
    case route(Int)
    case unplanned
}

enum DayReorderItem: Hashable {
    case place(markerID: String, route: Int?)
    /// Schedule and transport under a route place; hidden while a handle is held.
    case detail(markerID: String, route: Int)
    case placeholder
}

/// Native UICollectionView reordering for the day editor. The system owns lifting,
/// gap animation, auto-scrolling and cross-section moves; the final order is
/// committed once, after the drop.
struct DayPlaceReorderList: UIViewControllerRepresentable {
    let sections: [(section: DayReorderSection, items: [DayReorderItem])]
    let canReorder: Bool
    let header: AnyView?
    let sectionHeader: (DayReorderSection) -> AnyView
    let cell: (DayReorderItem) -> AnyView
    let onSelect: (DayReorderItem) -> Void
    /// Receives each route's final marker order; returns false to restore the model order.
    let commit: ([[String]]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let coordinator = context.coordinator
        let layout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
            configuration.backgroundColor = .systemBackground
            configuration.showsSeparators = false
            configuration.headerMode = .supplementary
            configuration.headerTopPadding = 8
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        let globalHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60)),
            elementKind: Coordinator.globalHeaderKind, alignment: .top)
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.boundarySupplementaryItems = [globalHeader]
        layout.configuration = configuration

        let controller = UICollectionViewController(collectionViewLayout: layout)
        let collectionView = controller.collectionView!
        collectionView.backgroundColor = .systemBackground
        collectionView.isEditing = true
        collectionView.allowsSelectionDuringEditing = true
        collectionView.dragInteractionEnabled = true
        collectionView.reorderingCadence = .immediate
        collectionView.delegate = coordinator
        collectionView.dragDelegate = coordinator
        collectionView.dropDelegate = coordinator
        collectionView.accessibilityIdentifier = "day-place-reorder-list"
        let handleWatcher = HandleTouchRecognizer(target: nil, action: nil)
        handleWatcher.onBegan = { [unowned coordinator] point in coordinator.handleTouchBegan(at: point) }
        handleWatcher.onEnded = { [unowned coordinator] in coordinator.handleTouchEnded() }
        collectionView.addGestureRecognizer(handleWatcher)
        coordinator.install(on: collectionView)
        coordinator.apply(animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(animated: true)
    }

    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
        static let globalHeaderKind = "day-reorder-global-header"
        var parent: DayPlaceReorderList
        private var dataSource: UICollectionViewDiffableDataSource<DayReorderSection, DayReorderItem>?
        private weak var collectionView: UICollectionView?
        private var reordering = false
        private var compact = false
        private var dragging = false
        private var insetCompensation: CGFloat = 0
        static let handleWidth: CGFloat = 56

        init(parent: DayPlaceReorderList) { self.parent = parent }

        func handleTouchBegan(at point: CGPoint) {
            guard parent.canReorder, !compact, let collectionView, let dataSource,
                  let indexPath = collectionView.indexPathForItem(at: point),
                  case .place = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath),
                  collectionView.convert(point, to: cell).x > cell.bounds.maxX - Self.handleWidth else { return }
            compactForDrag(at: indexPath)
        }

        private func compactForDrag(at indexPath: IndexPath) {
            guard !compact, let collectionView, let dataSource,
                  let cell = collectionView.cellForItem(at: indexPath) else { return }
            let anchor = dataSource.itemIdentifier(for: indexPath)
            let screenY = cell.frame.minY - collectionView.contentOffset.y
            compact = true
            dataSource.apply(modelSnapshot(), animatingDifferences: false)
            collectionView.layoutIfNeeded()
            // Keep the held row under the finger after the rows above it collapse.
            guard let anchor, let newPath = dataSource.indexPath(for: anchor),
                  let frame = collectionView.layoutAttributesForItem(at: newPath)?.frame else { return }
            var offset = frame.minY - screenY
            let minimum = -collectionView.adjustedContentInset.top
            if offset < minimum {
                insetCompensation = minimum - offset
                collectionView.contentInset.top += insetCompensation
                offset = -collectionView.adjustedContentInset.top
            }
            collectionView.contentOffset.y = offset
        }

        func handleTouchEnded() {
            // The reorder accessory's own gesture takes over the touch and reports
            // nothing until the drop, so wait until no gesture is still tracking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.compact else { return }
                if self.dragging || self.reordering || self.isTracking() { self.handleTouchEnded(); return }
                self.expand()
            }
        }

        private func isTracking() -> Bool {
            guard let collectionView else { return false }
            if collectionView.hasActiveDrag { return true }
            func active(_ view: UIView) -> Bool {
                (view.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
                    || view.subviews.contains(where: active)
            }
            return active(collectionView)
        }

        private func expand() {
            guard compact, let collectionView else { return }
            compact = false
            if insetCompensation != 0 {
                collectionView.contentInset.top -= insetCompensation
                insetCompensation = 0
            }
            apply(animated: true)
        }

        func install(on collectionView: UICollectionView) {
            self.collectionView = collectionView
            let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DayReorderItem> { [unowned self] cell, _, item in
                cell.contentConfiguration = UIHostingConfiguration { self.parent.cell(item) }
                    .margins(.all, 0).margins(.leading, 16)
                    .margins(.trailing, { if case .detail = item { return 16 } else { return 0 } }())
                    .minSize(height: 0)
                var background = UIBackgroundConfiguration.listPlainCell()
                background.backgroundColor = .systemBackground
                cell.backgroundConfiguration = background
                if case .place = item, self.parent.canReorder {
                    cell.accessories = [.reorder(displayed: .always)]
                } else {
                    cell.accessories = []
                }
            }
            let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
                elementKind: UICollectionView.elementKindSectionHeader) { [unowned self] header, _, indexPath in
                guard let section = self.dataSource?.sectionIdentifier(for: indexPath.section) else { return }
                header.contentConfiguration = UIHostingConfiguration { self.parent.sectionHeader(section) }.margins(.all, 0)
                header.backgroundConfiguration = .clear()
            }
            let globalRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
                elementKind: Self.globalHeaderKind) { [unowned self] header, _, _ in
                header.contentConfiguration = UIHostingConfiguration { self.parent.header ?? AnyView(EmptyView()) }.margins(.all, 0)
                header.backgroundConfiguration = .clear()
            }
            let dataSource = UICollectionViewDiffableDataSource<DayReorderSection, DayReorderItem>(collectionView: collectionView) { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            }
            dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
                kind == Self.globalHeaderKind
                    ? collectionView.dequeueConfiguredReusableSupplementary(using: globalRegistration, for: indexPath)
                    : collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            }
            dataSource.reorderingHandlers.canReorderItem = { [unowned self] item in
                if case .place = item { return self.parent.canReorder }
                return false
            }
            dataSource.reorderingHandlers.willReorder = { [unowned self] _ in self.reordering = true }
            dataSource.reorderingHandlers.didReorder = { [unowned self] transaction in
                self.reordering = false
                self.finishReorder(transaction.finalSnapshot)
            }
            self.dataSource = dataSource
        }

        private func modelSnapshot() -> NSDiffableDataSourceSnapshot<DayReorderSection, DayReorderItem> {
            var snapshot = NSDiffableDataSourceSnapshot<DayReorderSection, DayReorderItem>()
            for entry in parent.sections {
                snapshot.appendSections([entry.section])
                snapshot.appendItems(compact ? entry.items.filter {
                    if case .detail = $0 { return false }
                    return true
                } : entry.items, toSection: entry.section)
            }
            return snapshot
        }

        func apply(animated: Bool) {
            guard let dataSource, let collectionView, !reordering, !compact, !collectionView.hasActiveDrag else { return }
            var snapshot = modelSnapshot()
            let structureChanged = snapshot.sectionIdentifiers != dataSource.snapshot().sectionIdentifiers
                || snapshot.itemIdentifiers != dataSource.snapshot().itemIdentifiers
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: animated && structureChanged && !UIAccessibility.isReduceMotionEnabled)
            for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
                guard let header = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath) as? UICollectionViewListCell,
                      let section = dataSource.sectionIdentifier(for: indexPath.section) else { continue }
                header.contentConfiguration = UIHostingConfiguration { self.parent.sectionHeader(section) }.margins(.all, 0)
            }
        }

        private func finishReorder(_ snapshot: NSDiffableDataSourceSnapshot<DayReorderSection, DayReorderItem>) {
            let orders: [[String]] = snapshot.sectionIdentifiers.compactMap { section in
                guard case .route = section else { return nil }
                return snapshot.itemIdentifiers(inSection: section).compactMap { item in
                    if case let .place(markerID, _) = item { return markerID }
                    return nil
                }
            }
            if !parent.commit(orders) {
                dataSource?.apply(modelSnapshot(), animatingDifferences: false)
            }
            // Wait for SwiftUI to publish the committed model before restoring details.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.dragging else { return }
                self.expand()
            }
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) { dragging = true }

        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
            dragging = false
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.reordering else { return }
                self.expand()
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
            parent.onSelect(item)
        }

        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            guard parent.canReorder, let item = dataSource?.itemIdentifier(for: indexPath), case .place = item else { return [] }
            // Capture identity before compacting changes the diffable index paths.
            compactForDrag(at: indexPath)
            handleTouchEnded()
            let dragItem = UIDragItem(itemProvider: NSItemProvider())
            dragItem.localObject = item
            return [dragItem]
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            guard session.localDragSession != nil, collectionView.hasActiveDrag else { return UICollectionViewDropProposal(operation: .forbidden) }
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }

        // Local moves are committed by the diffable data source's reordering handlers.
        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {}
    }
}

/// Observes touch-down/up without ever recognizing, so taps, scrolling and the
/// system reorder gesture are unaffected.
private final class HandleTouchRecognizer: UIGestureRecognizer {
    var onBegan: ((CGPoint) -> Void)?
    var onEnded: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { onBegan?(touch.location(in: view)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish() }
    private func finish() {
        state = .failed
        onEnded?()
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
