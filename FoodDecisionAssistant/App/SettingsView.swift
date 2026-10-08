import SwiftUI

struct SettingsView: View {
    @State private var isShowingGoalSettings = false
    @State private var isShowingBackup = false

    var body: some View {
        Form {
            Section {
                Button("每日预算与目标", systemImage: "slider.horizontal.3") {
                    isShowingGoalSettings = true
                }
            } header: {
                Text("营养设置")
            } footer: {
                Text("热量、碳水与脂肪使用预算；蛋白质与纤维使用目标；饱和脂肪使用上限。")
            }

            Section {
                Button("本地备份", systemImage: "externaldrive") {
                    isShowingBackup = true
                }
            } header: {
                Text("数据保护")
            } footer: {
                Text("导出与验证恢复沿用现有本地备份流程，不自动上传个人数据。")
            }
        }
        .navigationTitle(AppTab.settings.title)
        .sheet(isPresented: $isShowingGoalSettings) {
            // The existing form owns validation, saving and unsaved-draft protection.
            // Today re-reads the same store when its tab is selected again.
            GoalSettingsView(onSaved: {})
        }
        .sheet(isPresented: $isShowingBackup) {
            BackupManagementView()
        }
    }
}
