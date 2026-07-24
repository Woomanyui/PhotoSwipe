import SwiftUI

struct PermissionView: View {
    @EnvironmentObject private var library: PhotoLibraryService

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 126, height: 126)
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("整理照片，留下回忆")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("左滑待删除 · 右滑保留 · 上滑收藏")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("照片只在你的设备上处理", systemImage: "lock.shield.fill")
                Label("删除前会再次统一确认", systemImage: "checkmark.shield.fill")
                Label("随时可以撤销上一步", systemImage: "arrow.uturn.backward.circle.fill")
            }
            .font(.subheadline)
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))

            Spacer()
            Button {
                Task { await library.requestAccess() }
            } label: {
                Text("选择照片并开始")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("PhotoSwipe 不会上传你的照片")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }
}
