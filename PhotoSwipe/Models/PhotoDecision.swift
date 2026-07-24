import Foundation

enum PhotoDecision: String {
    case delete
    case keep
    case favorite
    case album
}

struct DecisionRecord {
    let assetIdentifier: String
    let decision: PhotoDecision
    let wasFavorite: Bool
    let albumIdentifier: String?
}

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let assetCount: Int
}
