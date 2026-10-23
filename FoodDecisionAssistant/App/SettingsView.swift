import SwiftUI

struct SettingsView: View {
    @State private var isShowingGoalSettings = false
    @State private var isShowingBackup = false
    @State private var isShowingGoalHistory = false

    var body: some View {
        Form {
            Section {
                Button {
                    isShowingGoalSettings = true
                } label: {
                    SettingsEntryLabel(title: "每日预算与目标", systemImage: "slider.horizontal.3", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.goalSettings")
                Button {
                    isShowingGoalHistory = true
                } label: {
                    SettingsEntryLabel(title: "目标历史", systemImage: "clock.arrow.circlepath", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.goalHistory")
            } header: {
                Text("营养设置")
            } footer: {
                Text("热量、碳水与脂肪使用预算；蛋白质与纤维使用目标；饱和脂肪使用上限。")
            }

            Section {
                Button {
                    isShowingBackup = true
                } label: {
                    SettingsEntryLabel(title: "本地备份", systemImage: "externaldrive", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.backup")
            } header: {
                Text("数据保护")
            } footer: {
                Text("导出与验证恢复沿用现有本地备份流程，不自动上传个人数据。")
            }

            Section {
                NavigationLink(value: PersonalFoodsRoute()) {
                    SettingsEntryLabel(title: "我的食物", systemImage: "fork.knife", showsDisclosure: false)
                }
                .accessibilityIdentifier("settings.myFoods")
                NavigationLink(value: FoodSourcesRoute()) {
                    SettingsEntryLabel(title: "数据来源与许可", systemImage: "doc.text", showsDisclosure: false)
                }
                .accessibilityIdentifier("settings.foodSources")
            }
        }
        .accessibilityIdentifier("settings.form")
        .navigationTitle(AppTab.settings.title)
        .navigationDestination(for: FoodSourcesRoute.self) { _ in
            FoodSourcesView()
        }
        .navigationDestination(for: PersonalFoodsRoute.self) { _ in
            MyFoodsView()
        }
        .sheet(isPresented: $isShowingGoalSettings) {
            // The existing form owns validation, saving and unsaved-draft protection.
            // Today re-reads the same store when its tab is selected again.
            GoalSettingsView(onSaved: {})
        }
        .sheet(isPresented: $isShowingBackup) {
            BackupManagementView()
        }
        .sheet(isPresented: $isShowingGoalHistory) {
            GoalHistoryView()
        }
    }
}
