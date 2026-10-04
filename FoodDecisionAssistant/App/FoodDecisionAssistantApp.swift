import SwiftData
import SwiftUI

@main
struct ShiHengApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema(versionedSchema: VersionedSchemaV1.self)
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create the SwiftData model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
