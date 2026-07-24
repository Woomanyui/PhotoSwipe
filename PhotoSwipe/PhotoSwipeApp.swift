import SwiftUI

@main
struct PhotoSwipeApp: App {
    @StateObject private var library = PhotoLibraryService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
