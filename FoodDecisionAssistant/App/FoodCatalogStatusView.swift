import SwiftUI

struct FoodCatalogStatusView: View {
    let isUnavailable: Bool
    let conflictCount: Int
    let retry: () -> Void

    var body: some View {
        if isUnavailable {
            VStack(alignment: .leading, spacing: 8) {
                Label("完整食物目录尚未载入，已有本地食物仍可使用。", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试载入食物目录", action: retry)
                    .accessibilityIdentifier("food.catalog.retry")
            }
        }
        if conflictCount > 0 {
            Text("有 \(conflictCount) 项目录内容与本地不同，已保留本地数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("food.catalog.conflicts")
        }
    }
}
