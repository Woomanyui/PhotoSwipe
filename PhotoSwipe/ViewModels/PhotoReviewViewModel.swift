import Photos
import UIKit

@MainActor
final class PhotoReviewViewModel: ObservableObject {
    @Published private(set) var currentIndex = 0
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var currentLivePhoto: PHLivePhoto?
    @Published private(set) var pendingDeletionIDs: Set<String> = []
    @Published private(set) var keptCount = 0
    @Published private(set) var favoriteCount = 0
    @Published private(set) var albumCount = 0
    @Published private(set) var isAddingToAlbum = false
    @Published private(set) var isLoadingImage = false
    @Published var isShowingSummary = false
    @Published var errorMessage: String?

    private var history: [DecisionRecord] = []
    private var imageLoadTask: Task<Void, Never>?
    private var livePhotoLoadTask: Task<Void, Never>?
    private var similarityRemovedAssets: [String: PHAsset] = [:]
    private let reviewedAssetIDsKey = "reviewedAssetIdentifiers"

    var currentAsset: PHAsset? {
        guard libraryAssets.indices.contains(currentIndex) else { return nil }
        return libraryAssets[currentIndex]
    }

    var currentAssetIsLivePhoto: Bool {
        currentAsset?.mediaSubtypes.contains(.photoLive) == true
    }

    private var libraryAssets: [PHAsset] = []

    var reviewedCount: Int { history.count }
    var sourceReviewedCount: Int { currentIndex }
    var remainingCount: Int { max(libraryAssets.count - currentIndex, 0) }
    var remainingAssets: [PHAsset] {
        guard currentIndex < libraryAssets.count else { return [] }
        return Array(libraryAssets[currentIndex...])
    }
    var totalCount: Int { libraryAssets.count }
    var savedReviewedCount: Int { storedReviewedAssetIDs().count }
    var canUndo: Bool {
        guard let lastRecord = history.last else { return false }
        if similarityRemovedAssets[lastRecord.assetIdentifier] != nil {
            return true
        }
        guard currentIndex > 0 else { return false }
        return libraryAssets[currentIndex - 1].localIdentifier == lastRecord.assetIdentifier
    }

    func start(with assets: [PHAsset], library: PhotoLibraryService, targetSize: CGSize) {
        let reviewedAssetIDs = storedReviewedAssetIDs()
        let unreviewedAssets = assets.filter {
            !reviewedAssetIDs.contains($0.localIdentifier)
        }

        guard libraryAssets.map(\.localIdentifier) != unreviewedAssets.map(\.localIdentifier) else {
            if currentImage == nil { loadCurrentImage(library: library, targetSize: targetSize) }
            return
        }
        libraryAssets = unreviewedAssets
        currentIndex = 0
        pendingDeletionIDs = []
        keptCount = 0
        favoriteCount = 0
        albumCount = 0
        history = []
        similarityRemovedAssets = [:]
        loadCurrentImage(library: library, targetSize: targetSize)
    }

    func switchSource(
        to assets: [PHAsset],
        library: PhotoLibraryService,
        targetSize: CGSize
    ) {
        let reviewedAssetIDs = storedReviewedAssetIDs()
        libraryAssets = assets.filter {
            !reviewedAssetIDs.contains($0.localIdentifier)
        }
        currentIndex = 0
        currentImage = nil
        currentLivePhoto = nil
        isLoadingImage = false
        isShowingSummary = false
        loadCurrentImage(library: library, targetSize: targetSize)
    }

    func decide(
        _ decision: PhotoDecision,
        library: PhotoLibraryService,
        targetSize: CGSize,
        albumIdentifier: String? = nil
    ) {
        guard let asset = currentAsset else { return }
        history.append(
            DecisionRecord(
                assetIdentifier: asset.localIdentifier,
                decision: decision,
                wasFavorite: asset.isFavorite,
                albumIdentifier: albumIdentifier
            )
        )
        markAssetAsReviewed(asset.localIdentifier)

        switch decision {
        case .delete:
            pendingDeletionIDs.insert(asset.localIdentifier)
        case .keep:
            keptCount += 1
        case .favorite:
            favoriteCount += 1
            if !asset.isFavorite {
                Task {
                    do {
                        try await library.setFavorite(true, assetIdentifier: asset.localIdentifier)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        case .album:
            albumCount += 1
        }

        currentIndex += 1
        if currentIndex >= libraryAssets.count {
            isShowingSummary = true
        } else {
            loadCurrentImage(library: library, targetSize: targetSize)
        }
    }

    func addCurrentAsset(
        to album: PhotoAlbum,
        library: PhotoLibraryService,
        targetSize: CGSize
    ) async -> Bool {
        guard let asset = currentAsset, !isAddingToAlbum else { return false }
        isAddingToAlbum = true
        defer { isAddingToAlbum = false }

        do {
            try await library.addAsset(asset.localIdentifier, toAlbum: album.id)
            guard currentAsset?.localIdentifier == asset.localIdentifier else { return false }
            decide(
                .album,
                library: library,
                targetSize: targetSize,
                albumIdentifier: album.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createAlbumAndAddCurrentAsset(
        named name: String,
        library: PhotoLibraryService,
        targetSize: CGSize
    ) async -> Bool {
        guard let asset = currentAsset, !isAddingToAlbum else { return false }
        isAddingToAlbum = true
        defer { isAddingToAlbum = false }

        do {
            let album = try await library.createAlbum(
                named: name,
                adding: asset.localIdentifier
            )
            guard currentAsset?.localIdentifier == asset.localIdentifier else { return false }
            decide(
                .album,
                library: library,
                targetSize: targetSize,
                albumIdentifier: album.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func undo(library: PhotoLibraryService, targetSize: CGSize) {
        guard let last = history.last else { return }

        if let restoredAsset = similarityRemovedAssets.removeValue(
            forKey: last.assetIdentifier
        ) {
            history.removeLast()
            pendingDeletionIDs.remove(last.assetIdentifier)
            markAssetAsUnreviewed(last.assetIdentifier)
            libraryAssets.insert(restoredAsset, at: min(currentIndex, libraryAssets.count))
            currentImage = nil
            loadCurrentImage(library: library, targetSize: targetSize)
            return
        }

        guard currentIndex > 0 else { return }
        history.removeLast()
        currentIndex -= 1
        markAssetAsUnreviewed(last.assetIdentifier)

        switch last.decision {
        case .delete:
            pendingDeletionIDs.remove(last.assetIdentifier)
        case .keep:
            keptCount = max(keptCount - 1, 0)
        case .favorite:
            favoriteCount = max(favoriteCount - 1, 0)
            if !last.wasFavorite {
                Task {
                    do {
                        try await library.setFavorite(false, assetIdentifier: last.assetIdentifier)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        case .album:
            albumCount = max(albumCount - 1, 0)
            if let albumIdentifier = last.albumIdentifier {
                Task {
                    do {
                        try await library.removeAsset(
                            last.assetIdentifier,
                            fromAlbum: albumIdentifier
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        loadCurrentImage(library: library, targetSize: targetSize)
    }

    func queueSimilarPhotosForDeletion(
        _ assets: [PHAsset],
        library: PhotoLibraryService,
        targetSize: CGSize
    ) {
        let selectedIDs = Set(assets.map(\.localIdentifier))
        let newAssets = assets.filter {
            !pendingDeletionIDs.contains($0.localIdentifier)
                && similarityRemovedAssets[$0.localIdentifier] == nil
        }
        guard !newAssets.isEmpty else { return }

        for asset in newAssets {
            history.append(
                DecisionRecord(
                    assetIdentifier: asset.localIdentifier,
                    decision: .delete,
                    wasFavorite: asset.isFavorite,
                    albumIdentifier: nil
                )
            )
            similarityRemovedAssets[asset.localIdentifier] = asset
            pendingDeletionIDs.insert(asset.localIdentifier)
            markAssetAsReviewed(asset.localIdentifier)
        }

        let removedBeforeCurrent = libraryAssets
            .prefix(currentIndex)
            .filter { selectedIDs.contains($0.localIdentifier) }
            .count
        libraryAssets.removeAll {
            selectedIDs.contains($0.localIdentifier)
        }
        currentIndex = max(currentIndex - removedBeforeCurrent, 0)
        currentImage = nil
        currentLivePhoto = nil

        if currentIndex >= libraryAssets.count {
            isShowingSummary = true
        } else {
            loadCurrentImage(library: library, targetSize: targetSize)
        }
    }

    func commitDeletion(library: PhotoLibraryService) async -> Bool {
        do {
            try await library.deleteAssets(with: pendingDeletionIDs)
            isShowingSummary = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func continueReviewing() {
        isShowingSummary = false
    }

    func clearReviewHistory(
        using assets: [PHAsset],
        library: PhotoLibraryService,
        targetSize: CGSize
    ) {
        imageLoadTask?.cancel()
        livePhotoLoadTask?.cancel()
        UserDefaults.standard.removeObject(forKey: reviewedAssetIDsKey)
        libraryAssets = assets
        currentIndex = 0
        currentImage = nil
        currentLivePhoto = nil
        pendingDeletionIDs = []
        keptCount = 0
        favoriteCount = 0
        albumCount = 0
        history = []
        similarityRemovedAssets = [:]
        isShowingSummary = false
        loadCurrentImage(library: library, targetSize: targetSize)
    }

    private func loadCurrentImage(library: PhotoLibraryService, targetSize: CGSize) {
        imageLoadTask?.cancel()
        livePhotoLoadTask?.cancel()
        guard let asset = currentAsset else { return }

        currentImage = library.cachedImage(for: asset)
        currentLivePhoto = nil
        isLoadingImage = currentImage == nil
        let assetIdentifier = asset.localIdentifier
        imageLoadTask = Task {
            let image = await library.image(for: asset, targetSize: targetSize)
            guard !Task.isCancelled,
                  currentAsset?.localIdentifier == assetIdentifier else { return }
            if let image {
                currentImage = image
            }
            isLoadingImage = false
        }

        if asset.mediaSubtypes.contains(.photoLive) {
            livePhotoLoadTask = Task {
                let livePhoto = await library.livePhoto(
                    for: asset,
                    targetSize: targetSize
                )
                guard !Task.isCancelled,
                      currentAsset?.localIdentifier == assetIdentifier else { return }
                currentLivePhoto = livePhoto
            }
        }

        let firstPrefetchIndex = currentIndex + 1
        let prefetchEndIndex = min(firstPrefetchIndex + 4, libraryAssets.count)
        if firstPrefetchIndex < prefetchEndIndex {
            library.prefetchImages(
                for: Array(libraryAssets[firstPrefetchIndex..<prefetchEndIndex]),
                targetSize: targetSize
            )
        }
    }

    private func storedReviewedAssetIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: reviewedAssetIDsKey) ?? [])
    }

    private func markAssetAsReviewed(_ assetIdentifier: String) {
        var reviewedAssetIDs = storedReviewedAssetIDs()
        reviewedAssetIDs.insert(assetIdentifier)
        UserDefaults.standard.set(Array(reviewedAssetIDs), forKey: reviewedAssetIDsKey)
    }

    private func markAssetAsUnreviewed(_ assetIdentifier: String) {
        var reviewedAssetIDs = storedReviewedAssetIDs()
        reviewedAssetIDs.remove(assetIdentifier)
        UserDefaults.standard.set(Array(reviewedAssetIDs), forKey: reviewedAssetIDsKey)
    }
}
