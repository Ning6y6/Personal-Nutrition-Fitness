import SwiftData
import SwiftUI

@main
struct ShiHengApp: App {
    @State private var bootstrap = LocalStoreBootstrap()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = bootstrap.container {
                    ContentView()
                        .id(bootstrap.generation)
                        .modelContainer(container)
                } else {
                    StoreRecoveryView(bootstrap: bootstrap)
                }
            }
            .environment(\.storeBootstrap, bootstrap)
        }
    }
}
