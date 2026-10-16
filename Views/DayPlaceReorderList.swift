import SwiftUI
import UIKit

enum DayReorderSection: Hashable {
    case route(Int)
    case unplanned
}

enum DayReorderItem: Hashable {
    case place(markerID: String, route: Int?)
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

        init(parent: DayPlaceReorderList) { self.parent = parent }

        func install(on collectionView: UICollectionView) {
            self.collectionView = collectionView
            let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, DayReorderItem> { [unowned self] cell, _, item in
                cell.contentConfiguration = UIHostingConfiguration { self.parent.cell(item) }.margins(.all, 0)
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
                snapshot.appendItems(entry.items, toSection: entry.section)
            }
            return snapshot
        }

        func apply(animated: Bool) {
            guard let dataSource, let collectionView, !reordering, !collectionView.hasActiveDrag else { return }
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
            // The committed model renumbers routes; reload identities without a second animation.
            DispatchQueue.main.async { [weak self] in self?.apply(animated: false) }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
            parent.onSelect(item)
        }

        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            guard parent.canReorder, let item = dataSource?.itemIdentifier(for: indexPath), case .place = item else { return [] }
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
