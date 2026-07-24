import SwiftUI
import Photos
import PhotosUI
import UIKit

struct PhotoReviewView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @StateObject private var model = PhotoReviewViewModel()
    @State private var isShowingAlbumPicker = false
    @State private var isShowingSourceAlbumPicker = false
    @State private var isShowingDateFilter = false
    @State private var selectedSourceAlbum: PhotoAlbum?
    @State private var selectedDatePreset: PhotoDatePreset = .all
    @State private var customStartDate = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var customEndDate = Date()
    @State private var photoSortOrder: PhotoSortOrder = .newestFirst
    @State private var isShowingSimilarPhotos = false
    @State private var isScanningSimilarPhotos = false
    @State private var similarityScanProgress = 0.0
    @State private var similarPhotoGroups: [[PHAsset]] = []
    @State private var isShowingPrivacySettings = false

    private let imageTargetSize = CGSize(width: 1600, height: 2000)

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 18) {
                    progressHeader

                    Group {
                        if let asset = model.currentAsset {
                            SwipeCardView(
                                image: model.currentImage,
                                livePhoto: model.currentLivePhoto,
                                isLivePhoto: model.currentAssetIsLivePhoto,
                                onDecision: { decision in
                                    model.decide(
                                        decision,
                                        library: library,
                                        targetSize: imageTargetSize
                                    )
                                },
                                onAddToAlbum: {
                                    library.fetchAlbums()
                                    isShowingAlbumPicker = true
                                }
                            )
                            .id(asset.localIdentifier)
                        } else if library.assets.isEmpty {
                            emptyLibrary
                        } else {
                            completedState
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    actionBar
                }
                .padding(.horizontal, 18)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 10))
            }
            .navigationTitle("PhotoSwipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        library.fetchAlbums()
                        isShowingSourceAlbumPicker = true
                    } label: {
                        Label(
                            selectedSourceAlbum?.title ?? "全部照片",
                            systemImage: "rectangle.stack"
                        )
                    }

                    Button {
                        isShowingDateFilter = true
                    } label: {
                        Image(
                            systemName: selectedDatePreset == .all
                                ? "calendar"
                                : "calendar.badge.checkmark"
                        )
                    }
                    .accessibilityLabel("按日期整理")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        startSimilarityScan()
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("检查相似照片")
                    .disabled(model.remainingAssets.count < 2)

                    Button {
                        model.isShowingSummary = true
                    } label: {
                        Label(
                            "\(model.pendingDeletionIDs.count)",
                            systemImage: "trash"
                        )
                    }
                    .disabled(model.pendingDeletionIDs.isEmpty)

                    Button {
                        isShowingPrivacySettings = true
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                    .accessibilityLabel("安全与隐私")
                }
            }
            .sheet(isPresented: $model.isShowingSummary) {
                ReviewSummarySheet(
                    reviewedCount: model.reviewedCount,
                    deletionCount: model.pendingDeletionIDs.count,
                    keptCount: model.keptCount,
                    favoriteCount: model.favoriteCount,
                    albumCount: model.albumCount,
                    canContinue: model.remainingCount > 0,
                    onContinue: model.continueReviewing,
                    onDelete: {
                        Task {
                            if await model.commitDeletion(library: library) {
                                model.start(
                                    with: currentSourceAssets(),
                                    library: library,
                                    targetSize: imageTargetSize
                                )
                            }
                        }
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingAlbumPicker) {
                AlbumPickerSheet(
                    albums: library.albums.filter {
                        $0.id != selectedSourceAlbum?.id
                    },
                    isWorking: model.isAddingToAlbum,
                    onSelect: addCurrentPhoto(to:),
                    onCreate: createAlbumAndAddCurrentPhoto(named:)
                )
            }
            .sheet(isPresented: $isShowingDateFilter) {
                DateFilterSheet(
                    selectedPreset: selectedDatePreset,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate,
                    sortOrder: photoSortOrder,
                    onApply: applyDateFilter(
                        preset:startDate:endDate:sortOrder:
                    )
                )
            }
            .sheet(isPresented: $isShowingSimilarPhotos) {
                SimilarPhotosSheet(
                    groups: similarPhotoGroups,
                    isScanning: isScanningSimilarPhotos,
                    progress: similarityScanProgress,
                    onQueueDeletion: queueSimilarPhotosForDeletion(_:)
                )
                .environmentObject(library)
            }
            .sheet(isPresented: $isShowingSourceAlbumPicker) {
                SourceAlbumPickerSheet(
                    albums: library.albums,
                    selectedAlbumID: selectedSourceAlbum?.id,
                    onSelect: selectSourceAlbum(_:)
                )
            }
            .sheet(isPresented: $isShowingPrivacySettings) {
                SecurityPrivacySheet(
                    authorizationStatus: library.authorizationStatus,
                    savedReviewedCount: model.savedReviewedCount,
                    onManagePhotoAccess: managePhotoAccess,
                    onOpenSystemSettings: openSystemSettings,
                    onClearReviewHistory: {
                        model.clearReviewHistory(
                            using: currentSourceAssets(),
                            library: library,
                            targetSize: imageTargetSize
                        )
                    }
                )
            }
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onAppear {
                model.start(
                    with: library.assets,
                    library: library,
                    targetSize: imageTargetSize
                )
            }
            .onChange(of: library.assets.map(\.localIdentifier)) {
                model.switchSource(
                    to: currentSourceAssets(),
                    library: library,
                    targetSize: imageTargetSize
                )
            }
            .background {
                KeyboardCommandHost(
                    isEnabled: keyboardCommandsAreEnabled,
                    onLeftArrow: {
                        model.decide(
                            .delete,
                            library: library,
                            targetSize: imageTargetSize
                        )
                    },
                    onRightArrow: {
                        model.decide(
                            .keep,
                            library: library,
                            targetSize: imageTargetSize
                        )
                    },
                    onUpArrow: {
                        model.decide(
                            .favorite,
                            library: library,
                            targetSize: imageTargetSize
                        )
                    },
                    onDownArrow: showAlbumPicker
                )
                .frame(width: 1, height: 1)
            }
        }
    }

    private var keyboardCommandsAreEnabled: Bool {
        model.currentAsset != nil
            && !model.isShowingSummary
            && !isShowingAlbumPicker
            && !isShowingSourceAlbumPicker
            && !isShowingDateFilter
            && !isShowingSimilarPhotos
            && !isShowingPrivacySettings
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("当前来源已整理 \(model.sourceReviewedCount)")
                Spacer()
                Text("剩余 \(model.remainingCount)")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            ProgressView(
                value: Double(model.sourceReviewedCount),
                total: Double(max(model.totalCount, 1))
            )
            .tint(.purple)
        }
    }

    private var actionBar: some View {
        HStack {
            actionButton(
                symbol: "arrow.uturn.backward",
                color: .yellow,
                label: "撤销",
                disabled: !model.canUndo
            ) {
                model.undo(library: library, targetSize: imageTargetSize)
            }

            Spacer()
            actionButton(symbol: "trash.fill", color: .red, label: "删除") {
                model.decide(.delete, library: library, targetSize: imageTargetSize)
            }
            Spacer()
            actionButton(symbol: "heart.fill", color: .pink, label: "收藏") {
                model.decide(.favorite, library: library, targetSize: imageTargetSize)
            }
            Spacer()
            actionButton(symbol: "checkmark", color: .green, label: "保留") {
                model.decide(.keep, library: library, targetSize: imageTargetSize)
            }
        }
        .disabled(model.currentAsset == nil)
    }

    private func actionButton(
        symbol: String,
        color: Color,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.18), in: Circle())
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView(
            "没有可整理的照片",
            systemImage: "photo.on.rectangle.angled",
            description: Text("你可以在系统设置中调整允许访问的照片。")
        )
    }

    private var completedState: some View {
        ContentUnavailableView(
            selectedSourceAlbum == nil ? "今天整理完成" : "这个相册整理完成",
            systemImage: "sparkles",
            description: Text(
                selectedSourceAlbum == nil
                    ? "检查待删除照片，然后完成本次清理。"
                    : "你可以从左上角选择其他相册继续整理。"
            )
        )
    }

    private func currentSourceAssets() -> [PHAsset] {
        filteredSourceAssets(
            album: selectedSourceAlbum,
            preset: selectedDatePreset,
            startDate: customStartDate,
            endDate: customEndDate,
            sortOrder: photoSortOrder
        )
    }

    private func selectSourceAlbum(_ album: PhotoAlbum?) {
        selectedSourceAlbum = album
        model.switchSource(
            to: filteredSourceAssets(
                album: album,
                preset: selectedDatePreset,
                startDate: customStartDate,
                endDate: customEndDate,
                sortOrder: photoSortOrder
            ),
            library: library,
            targetSize: imageTargetSize
        )
        isShowingSourceAlbumPicker = false
    }

    private func applyDateFilter(
        preset: PhotoDatePreset,
        startDate: Date,
        endDate: Date,
        sortOrder: PhotoSortOrder
    ) {
        selectedDatePreset = preset
        customStartDate = startDate
        customEndDate = endDate
        photoSortOrder = sortOrder
        model.switchSource(
            to: filteredSourceAssets(
                album: selectedSourceAlbum,
                preset: preset,
                startDate: startDate,
                endDate: endDate,
                sortOrder: sortOrder
            ),
            library: library,
            targetSize: imageTargetSize
        )
        isShowingDateFilter = false
    }

    private func filteredSourceAssets(
        album: PhotoAlbum?,
        preset: PhotoDatePreset,
        startDate: Date,
        endDate: Date,
        sortOrder: PhotoSortOrder
    ) -> [PHAsset] {
        let sourceAssets = album.map {
            library.photoAssets(inAlbum: $0.id)
        } ?? library.assets
        let calendar = Calendar.current
        let now = Date()

        let dateInterval: DateInterval?
        switch preset {
        case .all:
            dateInterval = nil
        case .today:
            dateInterval = calendar.dateInterval(of: .day, for: now)
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            dateInterval = DateInterval(start: start, end: end)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            dateInterval = DateInterval(start: start, end: end)
        case .thisYear:
            dateInterval = calendar.dateInterval(of: .year, for: now)
        case .custom:
            let earlierDate = min(startDate, endDate)
            let laterDate = max(startDate, endDate)
            let start = calendar.startOfDay(for: earlierDate)
            let endDay = calendar.startOfDay(for: laterDate)
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? laterDate
            dateInterval = DateInterval(start: start, end: end)
        }

        let filteredAssets = sourceAssets.filter { asset in
            guard let dateInterval else { return true }
            guard let creationDate = asset.creationDate else { return false }
            return dateInterval.contains(creationDate)
        }

        return filteredAssets.sorted { first, second in
            let firstDate = first.creationDate ?? .distantPast
            let secondDate = second.creationDate ?? .distantPast
            switch sortOrder {
            case .newestFirst:
                return firstDate > secondDate
            case .oldestFirst:
                return firstDate < secondDate
            }
        }
    }

    private func addCurrentPhoto(to album: PhotoAlbum) {
        Task {
            if await model.addCurrentAsset(
                to: album,
                library: library,
                targetSize: imageTargetSize
            ) {
                isShowingAlbumPicker = false
            }
        }
    }

    private func showAlbumPicker() {
        guard model.currentAsset != nil else { return }
        library.fetchAlbums()
        isShowingAlbumPicker = true
    }

    private func createAlbumAndAddCurrentPhoto(named name: String) {
        Task {
            if await model.createAlbumAndAddCurrentAsset(
                named: name,
                library: library,
                targetSize: imageTargetSize
            ) {
                isShowingAlbumPicker = false
            }
        }
    }

    private func startSimilarityScan() {
        similarPhotoGroups = []
        similarityScanProgress = 0
        isScanningSimilarPhotos = true
        isShowingSimilarPhotos = true
        let assetsToScan = model.remainingAssets

        Task {
            let groups = await library.findSimilarPhotoGroups(
                in: assetsToScan
            ) { progress in
                similarityScanProgress = progress
            }
            similarPhotoGroups = groups
            isScanningSimilarPhotos = false
        }
    }

    private func queueSimilarPhotosForDeletion(_ assets: [PHAsset]) {
        model.queueSimilarPhotosForDeletion(
            assets,
            library: library,
            targetSize: imageTargetSize
        )
        isShowingSimilarPhotos = false
    }

    private func managePhotoAccess() {
        guard library.authorizationStatus == .limited else {
            openSystemSettings()
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            Task { @MainActor in
                library.refreshAuthorization()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum PhotoDatePreset: String, CaseIterable, Identifiable {
    case all
    case today
    case last7Days
    case last30Days
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部日期"
        case .today: "今天"
        case .last7Days: "最近 7 天"
        case .last30Days: "最近 30 天"
        case .thisYear: "今年"
        case .custom: "自定义日期"
        }
    }
}

private enum PhotoSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "最新优先"
        case .oldestFirst: "最早优先"
        }
    }
}

private struct DateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onApply: (PhotoDatePreset, Date, Date, PhotoSortOrder) -> Void

    @State private var preset: PhotoDatePreset
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var sortOrder: PhotoSortOrder

    init(
        selectedPreset: PhotoDatePreset,
        customStartDate: Date,
        customEndDate: Date,
        sortOrder: PhotoSortOrder,
        onApply: @escaping (PhotoDatePreset, Date, Date, PhotoSortOrder) -> Void
    ) {
        self.onApply = onApply
        _preset = State(initialValue: selectedPreset)
        _startDate = State(initialValue: customStartDate)
        _endDate = State(initialValue: customEndDate)
        _sortOrder = State(initialValue: sortOrder)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日期范围") {
                    Picker("日期范围", selection: $preset) {
                        ForEach(PhotoDatePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if preset == .custom {
                        DatePicker(
                            "开始日期",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "结束日期",
                            selection: $endDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section("照片顺序") {
                    Picker("照片顺序", selection: $sortOrder) {
                        ForEach(PhotoSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    onApply(preset, startDate, endDate, sortOrder)
                } label: {
                    Text("应用日期筛选")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("按日期整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SimilarPhotosSheet: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    let groups: [[PHAsset]]
    let isScanning: Bool
    let progress: Double
    let onQueueDeletion: ([PHAsset]) -> Void

    @State private var groupIndex = 0
    @State private var selectedAssetIDs: Set<String> = []
    @State private var fileSizes: [String: Int64] = [:]
    @State private var unavailableFileSizeIDs: Set<String> = []

    private var currentGroup: [PHAsset] {
        guard !groups.isEmpty else { return [] }
        return groups[min(groupIndex, groups.count - 1)]
    }

    private var selectedAssets: [PHAsset] {
        groups
            .flatMap { $0 }
            .reduce(into: [String: PHAsset]()) {
                $0[$1.localIdentifier] = $1
            }
            .values
            .filter { selectedAssetIDs.contains($0.localIdentifier) }
    }

    private var currentGroupSize: Int64 {
        currentGroup.reduce(0) {
            $0 + (fileSizes[$1.localIdentifier] ?? 0)
        }
    }

    private var currentGroupTaskID: String {
        currentGroup.map(\.localIdentifier).joined(separator: "|")
    }

    private var hasLoadedCurrentGroupSizes: Bool {
        currentGroup.allSatisfy {
            fileSizes[$0.localIdentifier] != nil
                || unavailableFileSizeIDs.contains($0.localIdentifier)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    VStack(spacing: 20) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text("正在检查相似照片…")
                            .font(.headline)
                        Text("最多检查当前整理范围内前 500 张本地可用照片")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                } else if groups.isEmpty {
                    ContentUnavailableView(
                        "没有发现相似照片",
                        systemImage: "checkmark.circle",
                        description: Text("当前相册与日期范围内没有明显相似的照片。")
                    )
                } else {
                    VStack(spacing: 14) {
                        HStack {
                            Button {
                                groupIndex = max(groupIndex - 1, 0)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(groupIndex == 0)

                            Spacer()
                            Text("相似组 \(groupIndex + 1) / \(groups.count)")
                                .font(.headline)
                            Spacer()

                            Button {
                                groupIndex = min(groupIndex + 1, groups.count - 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(groupIndex >= groups.count - 1)
                        }
                        .padding(.horizontal)

                        Text("点选准备删除的照片；每组至少保留一张")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if hasLoadedCurrentGroupSizes, currentGroupSize > 0 {
                            Text(
                                "本组共 \(ByteCountFormatter.string(fromByteCount: currentGroupSize, countStyle: .file))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if !hasLoadedCurrentGroupSizes {
                            Text("正在读取本组照片大小…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ],
                                spacing: 10
                            ) {
                                ForEach(currentGroup, id: \.localIdentifier) { asset in
                                    SimilarPhotoCard(
                                        asset: asset,
                                        isSelected: selectedAssetIDs.contains(
                                            asset.localIdentifier
                                        ),
                                        fileSize: fileSizes[asset.localIdentifier],
                                        groupSize: currentGroupSize,
                                        isFileSizeUnavailable: unavailableFileSizeIDs.contains(
                                            asset.localIdentifier
                                        )
                                    ) {
                                        toggleSelection(for: asset)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Button {
                            onQueueDeletion(selectedAssets)
                        } label: {
                            Label(
                                "加入待删除 \(selectedAssetIDs.count) 张",
                                systemImage: "trash"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selectedAssetIDs.isEmpty)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .task(id: currentGroupTaskID) {
                await loadFileSizesForCurrentGroup()
            }
            .navigationTitle("相似照片对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleSelection(for asset: PHAsset) {
        if selectedAssetIDs.contains(asset.localIdentifier) {
            selectedAssetIDs.remove(asset.localIdentifier)
            return
        }

        let selectedInCurrentGroup = currentGroup.filter {
            selectedAssetIDs.contains($0.localIdentifier)
        }.count
        guard selectedInCurrentGroup < currentGroup.count - 1 else { return }
        selectedAssetIDs.insert(asset.localIdentifier)
    }

    private func loadFileSizesForCurrentGroup() async {
        for asset in currentGroup where fileSizes[asset.localIdentifier] == nil {
            if Task.isCancelled { return }
            if let size = await library.photoFileSize(for: asset) {
                fileSizes[asset.localIdentifier] = size
            } else {
                unavailableFileSizeIDs.insert(asset.localIdentifier)
            }
        }
    }
}

private struct SimilarPhotoCard: View {
    @EnvironmentObject private var library: PhotoLibraryService

    let asset: PHAsset
    let isSelected: Bool
    let fileSize: Int64?
    let groupSize: Int64
    let isFileSizeUnavailable: Bool
    let action: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.title2)
                    .foregroundStyle(isSelected ? .red : .white)
                    .shadow(radius: 3)
                    .padding(8)
                }

                Label {
                    Text(
                        asset.creationDate?.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ) ?? "未知日期"
                    )
                    .lineLimit(1)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)

                Label {
                    if let fileSize {
                        let percentage = groupSize > 0
                            ? Double(fileSize) / Double(groupSize)
                            : 0
                        Text(
                            "\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) · 本组 \(percentage.formatted(.percent.precision(.fractionLength(1))))"
                        )
                    } else if isFileSizeUnavailable {
                        Text("原图未在本机，大小不可用")
                    } else {
                        Text("正在读取大小…")
                    }
                } icon: {
                    Image(systemName: "internaldrive")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Label(
                    "\(asset.pixelWidth) × \(asset.pixelHeight)",
                    systemImage: "rectangle.inset.filled"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(7)
            .background(
                isSelected ? Color.red.opacity(0.13) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            image = await library.image(
                for: asset,
                targetSize: CGSize(width: 900, height: 900)
            )
        }
    }
}

private struct SourceAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let albums: [PhotoAlbum]
    let selectedAlbumID: String?
    let onSelect: (PhotoAlbum?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                } label: {
                    sourceRow(
                        title: "全部照片",
                        count: nil,
                        isSelected: selectedAlbumID == nil,
                        symbol: "photo.on.rectangle.angled"
                    )
                }

                Section("我的相册") {
                    if albums.isEmpty {
                        Text("还没有自建相册")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(albums) { album in
                            Button {
                                onSelect(album)
                            } label: {
                                sourceRow(
                                    title: album.title,
                                    count: album.assetCount,
                                    isSelected: selectedAlbumID == album.id,
                                    symbol: "rectangle.stack"
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择整理相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sourceRow(
        title: String,
        count: Int?,
        isSelected: Bool,
        symbol: String
    ) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let count {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.purple)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let albums: [PhotoAlbum]
    let isWorking: Bool
    let onSelect: (PhotoAlbum) -> Void
    let onCreate: (String) -> Void

    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建相册") {
                    HStack {
                        TextField("相册名称", text: $newAlbumName)
                            .textInputAutocapitalization(.never)
                        Button("创建并添加") {
                            onCreate(newAlbumName)
                        }
                        .disabled(
                            newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isWorking
                        )
                    }
                }

                Section("已有相册") {
                    if albums.isEmpty {
                        Text("还没有可用的自建相册")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(albums) { album in
                            Button {
                                onSelect(album)
                            } label: {
                                Label(album.title, systemImage: "rectangle.stack")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(isWorking)
                        }
                    }
                }
            }
            .navigationTitle("加入相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("正在添加…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

private struct SecurityPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    let authorizationStatus: PHAuthorizationStatus
    let savedReviewedCount: Int
    let onManagePhotoAccess: () -> Void
    let onOpenSystemSettings: () -> Void
    let onClearReviewHistory: () -> Void

    @State private var isConfirmingHistoryClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("相册权限") {
                    LabeledContent("当前权限", value: authorizationTitle)

                    Button {
                        onManagePhotoAccess()
                    } label: {
                        Label(
                            authorizationStatus == .limited
                                ? "管理可访问的照片"
                                : "管理相册权限",
                            systemImage: "photo.badge.checkmark"
                        )
                    }

                    Button {
                        onOpenSystemSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gear")
                    }
                }

                Section("本机数据") {
                    LabeledContent("已整理记录", value: "\(savedReviewedCount) 张")
                    Text("App 只保存已整理照片的本地标识，不保存照片副本、相似度结果或照片文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("清除整理记录", role: .destructive) {
                        isConfirmingHistoryClear = true
                    }
                    .disabled(savedReviewedCount == 0)
                }

                Section("隐私说明") {
                    PrivacyStatementRow(
                        symbol: "iphone",
                        title: "仅在设备上处理",
                        detail: "照片读取、相似照片检查和整理记录都在这台 iPhone 上完成。"
                    )
                    PrivacyStatementRow(
                        symbol: "network.slash",
                        title: "不上传照片",
                        detail: "App 没有服务器、广告、分析或追踪 SDK，也不会发送照片数据。"
                    )
                    PrivacyStatementRow(
                        symbol: "trash.slash",
                        title: "删除由你确认",
                        detail: "照片先进入待删除列表，最终删除仍由 Apple 系统弹窗确认。"
                    )
                }

                Section("安全与隐私联系") {
                    Link(
                        destination: URL(string: "mailto:rey0619@outlook.com")!
                    ) {
                        Label("rey0619@outlook.com", systemImage: "envelope")
                    }
                    Text("如发现安全问题，请说明 App 版本、设备系统版本和复现步骤；不要在邮件中附上私人照片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("安全与隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "清除全部整理记录？",
                isPresented: $isConfirmingHistoryClear,
                titleVisibility: .visible
            ) {
                Button("清除整理记录", role: .destructive) {
                    onClearReviewHistory()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("照片不会被删除，但以前整理过的照片会重新出现在整理页面。当前待删除队列也会被清空。")
            }
        }
    }

    private var authorizationTitle: String {
        switch authorizationStatus {
        case .authorized: "完全访问"
        case .limited: "有限访问"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        case .notDetermined: "尚未选择"
        @unknown default: "未知"
        }
    }
}

private struct PrivacyStatementRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.purple)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct KeyboardCommandHost: UIViewControllerRepresentable {
    let isEnabled: Bool
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void
    let onUpArrow: () -> Void
    let onDownArrow: () -> Void

    func makeUIViewController(context: Context) -> KeyboardCommandController {
        let controller = KeyboardCommandController()
        update(controller)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: KeyboardCommandController,
        context: Context
    ) {
        update(uiViewController)
        if isEnabled {
            DispatchQueue.main.async {
                uiViewController.becomeFirstResponder()
            }
        }
    }

    private func update(_ controller: KeyboardCommandController) {
        controller.isEnabled = isEnabled
        controller.onLeftArrow = onLeftArrow
        controller.onRightArrow = onRightArrow
        controller.onUpArrow = onUpArrow
        controller.onDownArrow = onDownArrow
    }
}

private final class KeyboardCommandController: UIViewController {
    var isEnabled = false
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            command(
                input: UIKeyCommand.inputLeftArrow,
                action: #selector(pressLeftArrow),
                title: "删除照片"
            ),
            command(
                input: UIKeyCommand.inputRightArrow,
                action: #selector(pressRightArrow),
                title: "保留照片"
            ),
            command(
                input: UIKeyCommand.inputUpArrow,
                action: #selector(pressUpArrow),
                title: "收藏照片"
            ),
            command(
                input: UIKeyCommand.inputDownArrow,
                action: #selector(pressDownArrow),
                title: "加入相册"
            )
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    private func command(
        input: String,
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: [],
            action: action
        )
        command.discoverabilityTitle = title
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func pressLeftArrow() {
        if isEnabled { onLeftArrow?() }
    }

    @objc private func pressRightArrow() {
        if isEnabled { onRightArrow?() }
    }

    @objc private func pressUpArrow() {
        if isEnabled { onUpArrow?() }
    }

    @objc private func pressDownArrow() {
        if isEnabled { onDownArrow?() }
    }
}
