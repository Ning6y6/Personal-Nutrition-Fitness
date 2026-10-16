import FoodDecisionCore
import SwiftUI

struct GoalVersionDetailView: View {
    @Environment(\.appDateDisplay) private var dateDisplay

    let version: GoalVersion
    let status: String
    let referenceDay: GoalDay?

    var body: some View {
        Form {
            Section("生效与确认") {
                LabeledContent("生效日期", value: GoalDatePresentation.text(for: version.effectiveDay, referenceDay: referenceDay, display: dateDisplay))
                LabeledContent("当前状态", value: status)
                LabeledContent("确认时间") {
                    Text(dateDisplay.dateTimeWithSeconds(version.confirmedAt))
                        .accessibilityIdentifier("goalHistory.detail.confirmedAt")
                }
                LabeledContent("确认时区", value: version.timeZoneIdentifier)
            }
            Section("营养预算与目标") {
                LabeledContent("热量预算", value: KcalDisplay.amount(version.profile.energyKcal))
                    .accessibilityIdentifier("goalHistory.detail.energy")
                LabeledContent("蛋白质目标", value: "\(version.profile.proteinGrams.formatted()) g")
                LabeledContent("碳水预算", value: "\(version.profile.carbohydrateGrams.formatted()) g")
                LabeledContent("脂肪预算", value: "\(version.profile.fatGrams.formatted()) g")
                LabeledContent("饱和脂肪上限", value: optionalGrams(version.profile.saturatedFatLimitGrams))
                LabeledContent("纤维目标", value: optionalGrams(version.profile.fibreGrams))
            }
            Section {
                LabeledContent("目标来源", value: Self.sourceTitle(version.source))
                if let sourceNote = version.sourceNote {
                    Text(sourceNote)
                        .accessibilityIdentifier("goalHistory.detail.sourceNote")
                }
            } header: {
                Text("来源")
            } footer: {
                Text("来源由用户提供，系统未核实医疗建议。这个已确认版本仅供查看。")
            }
        }
        .accessibilityIdentifier("goalHistory.detail")
        .navigationTitle("目标版本详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionalGrams(_ value: Double?) -> String {
        value.map { "\($0.formatted()) g" } ?? "未设置"
    }

    static func sourceTitle(_ source: GoalSource) -> String {
        switch source {
        case .selfSelected: "自行选择"
        case .userProvidedReference: "参考已有建议"
        }
    }

}
