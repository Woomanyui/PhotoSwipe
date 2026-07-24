import Photos
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: PhotoLibraryService

    var body: some View {
        Group {
            switch library.authorizationStatus {
            case .authorized, .limited:
                PhotoReviewView()
            case .notDetermined:
                PermissionView()
            case .denied, .restricted:
                AccessDeniedView()
            @unknown default:
                AccessDeniedView()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            library.refreshAuthorization()
        }
    }
}

private struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 58))
                .foregroundStyle(.orange)
            Text("需要照片权限")
                .font(.title.bold())
            Text("请在系统设置中允许 PhotoSwipe 访问照片，才能开始整理。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("打开设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
