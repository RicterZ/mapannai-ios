import Foundation

enum LocationFollowMode: Equatable {
    case idle, centered, heading
    var next: Self { switch self { case .idle: .centered; case .centered: .heading; case .heading: .centered } }
    var symbol: String { self == .heading ? "location.fill" : "location" }
}
