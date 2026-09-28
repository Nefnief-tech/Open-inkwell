import SwiftUI

@main
struct InkwellApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
