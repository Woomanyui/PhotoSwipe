import SwiftUI

struct ReviewSummarySheet: View {
    let reviewedCount: Int
    let deletionCount: Int
    let keptCount: Int
    let favoriteCount: Int
    let albumCount: Int
    let canContinue: Bool
    let onContinue: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42))
                    .foregroundStyle(.purple)
                Text("已整理 \(reviewedCount) 张")
                    .font(.title2.bold())

                HStack(spacing: 12) {
                    stat("\(deletionCount)", "待删除", .red)
                    stat("\(keptCount)", "保留", .green)
                    stat("\(favoriteCount)", "收藏", .pink)
                    stat("\(albumCount)", "相册", .blue)
                }

                Text("点击删除后，iOS 仍会显示最终确认。删除的照片会进入系统“最近删除”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(role: .destructive, action: onDelete) {
                    Text(deletionCount == 0 ? "完成" : "确认删除 \(deletionCount) 张")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if canContinue {
                    Button("继续整理", action: onContinue)
                }
            }
            .padding(24)
            .navigationTitle("本次整理")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
