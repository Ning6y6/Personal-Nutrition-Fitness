import Foundation
import SwiftUI

/// Refreshes date display preferences without replacing view identity, drafts or numeric locale.
struct AppDateDisplayModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var display: AppDateDisplayContext
    let interfaceLanguage: String

    init(interfaceLanguage: String = "zh-Hans") {
        self.interfaceLanguage = interfaceLanguage
        _display = State(initialValue: AppDateDisplayContext(interfaceLanguage: interfaceLanguage))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.appDateDisplay, display)
            .onChange(of: interfaceLanguage) { refresh() }
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
                refresh()
            }
    }

    private func refresh() {
        display = AppDateDisplayContext(interfaceLanguage: interfaceLanguage)
    }
}
