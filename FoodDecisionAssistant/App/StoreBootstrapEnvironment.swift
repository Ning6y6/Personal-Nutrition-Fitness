import SwiftUI

extension EnvironmentValues {
    // Optional so previews can show their own in-memory container without opening a device store.
    @Entry var storeBootstrap: LocalStoreBootstrap?
}
