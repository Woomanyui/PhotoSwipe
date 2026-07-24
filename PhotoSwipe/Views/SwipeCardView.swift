import SwiftUI
import Photos
import PhotosUI

struct SwipeCardView: View {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    let isLivePhoto: Bool
    let onDecision: (PhotoDecision) -> Void
    let onAddToAlbum: () -> Void

    @State private var offset: CGSize = .zero
    @State private var isLeaving = false
    @State private var livePhotoPlaybackToken = 0

    private let threshold: CGFloat = 95

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.08))

            if let livePhoto {
                LivePhotoPlayerView(
                    livePhoto: livePhoto,
                    playbackToken: livePhotoPlaybackToken
                )
                .clipShape(RoundedRectangle(cornerRadius: 28))
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 28))
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            decisionOverlay

            if isLivePhoto {
                VStack {
                    HStack {
                        Button {
                            livePhotoPlaybackToken += 1
                        } label: {
                            Label("实况", systemImage: "livephoto")
                                .font(.caption.bold())
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.58), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(livePhoto == nil)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 22)))
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !isLeaving else { return }
                    offset = value.translation
                }
                .onEnded { value in
                    finishDrag(value.translation)
                }
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    @ViewBuilder
    private var decisionOverlay: some View {
        if abs(offset.width) > 24 || abs(offset.height) > 24 {
            VStack {
                if offset.height > abs(offset.width) {
                    Spacer()
                    badge("加入相册", symbol: "rectangle.stack.badge.plus", color: .blue)
                } else if offset.height < -abs(offset.width) {
                    badge("收藏", symbol: "heart.fill", color: .pink)
                    Spacer()
                } else {
                    HStack {
                        if offset.width > 0 {
                            badge("保留", symbol: "checkmark", color: .green)
                            Spacer()
                        } else {
                            Spacer()
                            badge("删除", symbol: "trash.fill", color: .red)
                        }
                    }
                    Spacer()
                }
            }
            .padding(24)
            .opacity(min(max(max(abs(offset.width), -offset.height) / threshold, 0), 1))
        }
    }

    private func badge(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.title3.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.58), in: Capsule())
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color, lineWidth: 2))
    }

    private func finishDrag(_ translation: CGSize) {
        if translation.height > threshold,
           abs(translation.height) > abs(translation.width) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                offset = .zero
            }
            onAddToAlbum()
        } else if translation.height < -threshold,
           abs(translation.height) > abs(translation.width) {
            leave(toward: CGSize(width: 0, height: -900), decision: .favorite)
        } else if translation.width < -threshold {
            leave(toward: CGSize(width: -700, height: translation.height), decision: .delete)
        } else if translation.width > threshold {
            leave(toward: CGSize(width: 700, height: translation.height), decision: .keep)
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                offset = .zero
            }
        }
    }

    private func leave(toward destination: CGSize, decision: PhotoDecision) {
        isLeaving = true
        withAnimation(.easeOut(duration: 0.16)) {
            offset = destination
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onDecision(decision)
        }
    }
}

private struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        let didChangePhoto = context.coordinator.livePhoto !== livePhoto
        if didChangePhoto {
            context.coordinator.livePhoto = livePhoto
            uiView.livePhoto = livePhoto
        }

        guard didChangePhoto
                || context.coordinator.lastPlaybackToken != playbackToken else {
            return
        }
        context.coordinator.lastPlaybackToken = playbackToken
        DispatchQueue.main.async {
            uiView.startPlayback(with: .full)
        }
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        uiView.stopPlayback()
    }

    final class Coordinator {
        var livePhoto: PHLivePhoto?
        var lastPlaybackToken = -1
    }
}
