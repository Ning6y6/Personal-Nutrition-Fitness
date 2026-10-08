import SwiftData
import SwiftUI

/// The shell owns presentation selection, not nutritional or persistent state.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: AppTab
    @State private var seedImportError: Error?

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                NavigationStack {
                    TodayView(isSelected: selectedTab == .today)
                }
            }
            Tab(AppTab.scan.title, systemImage: AppTab.scan.systemImage, value: AppTab.scan) {
                NavigationStack {
                    LabelScannerView()
                }
            }
            Tab(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage, value: AppTab.calendar) {
                NavigationStack {
                    NutritionCalendarView()
                }
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(DesignTokens.accent)
        .task { prepareFoodCatalog() }
        .alert(
            "无法准备食物库",
            isPresented: Binding(
                get: { seedImportError != nil },
                set: { if !$0 { seedImportError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(seedImportError?.localizedDescription ?? "")
        }
    }

    private func prepareFoodCatalog() {
        do {
            try SeedFoodCatalog.importIfNeeded(into: modelContext)
        } catch {
            seedImportError = error
        }
    }
}
