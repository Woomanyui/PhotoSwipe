import Photos
import UIKit

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var albums: [PhotoAlbum] = []

    private let imageManager = PHCachingImageManager()
    private let previewImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()
    private let highQualityImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 6
        return cache
    }()
    private let fileSizeCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 200
        return cache
    }()
    private let livePhotoCache: NSCache<NSString, PHLivePhoto> = {
        let cache = NSCache<NSString, PHLivePhoto>()
        cache.countLimit = 4
        return cache
    }()

    func requestAccess() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if canReadLibrary {
            fetchAssets()
            fetchAlbums()
        }
    }

    func refreshAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if canReadLibrary {
            fetchAssets()
            fetchAlbums()
        }
    }

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )

        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }
        assets = fetched
    }

    func fetchAlbums() {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var fetchedAlbums: [PhotoAlbum] = []
        result.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle, !title.isEmpty else { return }
            let assetCount = PHAsset.fetchAssets(
                in: collection,
                options: self.imageFetchOptions()
            ).count
            fetchedAlbums.append(
                PhotoAlbum(
                    id: collection.localIdentifier,
                    title: title,
                    assetCount: assetCount
                )
            )
        }
        albums = fetchedAlbums.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func photoAssets(inAlbum albumIdentifier: String) -> [PHAsset] {
        let albumResult = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let album = albumResult.firstObject else { return [] }

        let result = PHAsset.fetchAssets(in: album, options: imageFetchOptions())
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }
        return fetched
    }

    func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let cacheKey = asset.localIdentifier as NSString
        if let cachedImage = highQualityImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image, !isDegraded {
                    self.highQualityImageCache.setObject(image, forKey: cacheKey)
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: image)
                } else {
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let hasError = info?[PHImageErrorKey] != nil
                    guard (isCancelled || hasError), !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func cachedImage(for asset: PHAsset) -> UIImage? {
        let cacheKey = asset.localIdentifier as NSString
        return highQualityImageCache.object(forKey: cacheKey)
            ?? previewImageCache.object(forKey: cacheKey)
    }

    func livePhoto(for asset: PHAsset, targetSize: CGSize) async -> PHLivePhoto? {
        guard asset.mediaSubtypes.contains(.photoLive) else { return nil }
        let cacheKey = asset.localIdentifier as NSString
        if let cachedLivePhoto = livePhotoCache.object(forKey: cacheKey) {
            return cachedLivePhoto
        }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            imageManager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let livePhoto, !isDegraded {
                    self.livePhotoCache.setObject(livePhoto, forKey: cacheKey)
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: livePhoto)
                } else {
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let hasError = info?[PHImageErrorKey] != nil
                    guard (isCancelled || hasError), !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func photoFileSize(for asset: PHAsset) async -> Int64? {
        let cacheKey = asset.localIdentifier as NSString
        if let cachedSize = fileSizeCache.object(forKey: cacheKey) {
            return cachedSize.int64Value
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto
        }) ?? resources.first else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        let size: Int64? = await withCheckedContinuation { continuation in
            var byteCount: Int64 = 0
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { data in
                byteCount += Int64(data.count)
            } completionHandler: { error in
                continuation.resume(returning: error == nil ? byteCount : nil)
            }
        }

        if let size {
            fileSizeCache.setObject(NSNumber(value: size), forKey: cacheKey)
        }
        return size
    }

    func prefetchImages(for assets: [PHAsset], targetSize: CGSize) {
        let uncachedAssets = assets.filter {
            let cacheKey = $0.localIdentifier as NSString
            return highQualityImageCache.object(forKey: cacheKey) == nil
                && previewImageCache.object(forKey: cacheKey) == nil
        }
        guard !uncachedAssets.isEmpty else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        imageManager.startCachingImages(
            for: uncachedAssets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        )

        for asset in uncachedAssets {
            let cacheKey = asset.localIdentifier as NSString
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [previewImageCache] image, _ in
                if let image {
                    previewImageCache.setObject(image, forKey: cacheKey)
                }
            }
        }
    }

    func findSimilarPhotoGroups(
        in assets: [PHAsset],
        maxAssets: Int = 500,
        progress: @escaping (Double) -> Void
    ) async -> [[PHAsset]] {
        let candidates = Array(assets.prefix(maxAssets))
        guard candidates.count > 1 else {
            progress(1)
            return []
        }

        var hashedAssets: [(asset: PHAsset, hash: UInt64)] = []
        hashedAssets.reserveCapacity(candidates.count)

        for (index, asset) in candidates.enumerated() {
            if Task.isCancelled { return [] }
            if let image = await similarityThumbnail(for: asset),
               let hash = differenceHash(for: image) {
                hashedAssets.append((asset, hash))
            }
            progress(Double(index + 1) / Double(candidates.count))
            if index.isMultiple(of: 8) {
                await Task.yield()
            }
        }

        guard hashedAssets.count > 1 else { return [] }

        var parents = Array(hashedAssets.indices)

        func findRoot(_ index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func union(_ first: Int, _ second: Int) {
            let firstRoot = findRoot(first)
            let secondRoot = findRoot(second)
            if firstRoot != secondRoot {
                parents[secondRoot] = firstRoot
            }
        }

        for firstIndex in hashedAssets.indices {
            for secondIndex in hashedAssets.indices where secondIndex > firstIndex {
                let firstAsset = hashedAssets[firstIndex].asset
                let secondAsset = hashedAssets[secondIndex].asset
                let firstRatio = Double(firstAsset.pixelWidth) / Double(max(firstAsset.pixelHeight, 1))
                let secondRatio = Double(secondAsset.pixelWidth) / Double(max(secondAsset.pixelHeight, 1))
                let ratioDifference = abs(firstRatio - secondRatio) / max(firstRatio, secondRatio, 0.01)
                guard ratioDifference < 0.08 else { continue }

                let bitDifference = (
                    hashedAssets[firstIndex].hash ^ hashedAssets[secondIndex].hash
                ).nonzeroBitCount
                let timeDifference: TimeInterval
                if let firstDate = firstAsset.creationDate,
                   let secondDate = secondAsset.creationDate {
                    timeDifference = abs(firstDate.timeIntervalSince(secondDate))
                } else {
                    timeDifference = .infinity
                }

                let threshold = timeDifference <= 10 * 60 ? 10 : 4
                if bitDifference <= threshold {
                    union(firstIndex, secondIndex)
                }
            }
        }

        var groupedAssets: [Int: [PHAsset]] = [:]
        for index in hashedAssets.indices {
            groupedAssets[findRoot(index), default: []].append(hashedAssets[index].asset)
        }

        return groupedAssets.values
            .filter { $0.count > 1 }
            .map {
                $0.sorted {
                    ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
                }
            }
            .sorted {
                ($0.first?.creationDate ?? .distantPast)
                    > ($1.first?.creationDate ?? .distantPast)
            }
    }

    func setFavorite(_ favorite: Bool, assetIdentifier: String) async throws {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = result.firstObject else { return }

        try await performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = favorite
        }
    }

    func addAsset(_ assetIdentifier: String, toAlbum albumIdentifier: String) async throws {
        let assetResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        )
        let albumResult = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let asset = assetResult.firstObject,
              let album = albumResult.firstObject else {
            throw libraryError("找不到所选照片或相册。")
        }

        var didCreateRequest = false
        try await performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            didCreateRequest = true
            request.addAssets([asset] as NSArray)
        }
        guard didCreateRequest else {
            throw libraryError("这个相册不允许添加照片。")
        }
        fetchAlbums()
    }

    func createAlbum(named name: String, adding assetIdentifier: String) async throws -> PhotoAlbum {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw libraryError("请输入相册名称。")
        }

        var createdAlbumIdentifier: String?
        try await performChanges {
            let request = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: trimmedName)
            createdAlbumIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let createdAlbumIdentifier else {
            throw libraryError("无法创建相册。")
        }

        try await addAsset(assetIdentifier, toAlbum: createdAlbumIdentifier)
        return PhotoAlbum(id: createdAlbumIdentifier, title: trimmedName, assetCount: 1)
    }

    func removeAsset(_ assetIdentifier: String, fromAlbum albumIdentifier: String) async throws {
        let assetResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        )
        let albumResult = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let asset = assetResult.firstObject,
              let album = albumResult.firstObject else { return }

        var didCreateRequest = false
        try await performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            didCreateRequest = true
            request.removeAssets([asset] as NSArray)
        }
        guard didCreateRequest else {
            throw libraryError("无法从这个相册移除照片。")
        }
        fetchAlbums()
    }

    func deleteAssets(with identifiers: Set<String>) async throws {
        guard !identifiers.isEmpty else { return }
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(identifiers),
            options: nil
        )
        try await performChanges {
            PHAssetChangeRequest.deleteAssets(result)
        }
        fetchAssets()
        fetchAlbums()
    }

    private func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "PhotoSwipe.PhotoLibrary",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "照片图库未完成更改。"]
                        )
                    )
                }
            }
        }
    }

    private func libraryError(_ message: String) -> NSError {
        NSError(
            domain: "PhotoSwipe.PhotoLibrary",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func imageFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        return options
    }

    private func similarityThumbnail(for asset: PHAsset) async -> UIImage? {
        if let cachedImage = cachedImage(for: asset) {
            return cachedImage
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 128, height: 128),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    hasResumed = true
                    continuation.resume(returning: image)
                } else if !isDegraded {
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func differenceHash(for image: UIImage) -> UInt64? {
        let size = CGSize(width: 9, height: 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalizedImage = UIGraphicsImageRenderer(size: size, format: format).image {
            _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = normalizedImage.cgImage else { return nil }

        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        guard let context = CGContext(
            data: &pixels,
            width: 9,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 9,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<8 {
            for column in 0..<8 {
                if pixels[row * 9 + column] > pixels[row * 9 + column + 1] {
                    hash |= UInt64(1) << UInt64(bit)
                }
                bit += 1
            }
        }
        return hash
    }
}
