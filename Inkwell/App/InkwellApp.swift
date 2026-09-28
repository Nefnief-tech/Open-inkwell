import SwiftUI

@main
struct InkwellApp: App {
    @State private var hands = HandStore()
    @State private var documents = DocumentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hands)
                .environment(documents)
        }
    }
}
