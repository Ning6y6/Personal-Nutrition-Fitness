import FoodDecisionCore
import SwiftUI

struct FibreSummaryPresentation: Equatable, Sendable {
    let amountText: String
    let detailText: String?
    let exactGrams: Double?

    init(summary: FibreIntakeSummary?) {
        exactGrams = summary?.exactGrams
        guard let summary else {
            amountText = "无法安全计算"
            detailText = "纤维小计超出可计算范围，未显示为0。"
            return
        }
        guard summary.hasRecords else {
            amountText = "尚无可汇总分项"
            detailText = nil
            return
        }
        if let exact = summary.exactGrams {
            amountText = "\(Self.formatted(exact)) g"
            detailText = nil
        } else if let known = summary.knownSubtotalGrams {
            amountText = "至少 \(Self.formattedLowerBound(known)) g"
            detailText = "\(summary.unknownComponentCount)个分项纤维未知；仅展示已知小计，总量与缺口未确定。"
        } else {
            amountText = "未知"
            detailText = "全部\(summary.unknownComponentCount)个分项缺少纤维数据；未显示为0。"
        }
    }

    static func formatted(_ value: Double) -> String {
        if value > 0, value < 0.1 {
            return value.formatted(.number.precision(.significantDigits(1...3)))
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func formattedLowerBound(_ value: Double) -> String {
        // Do not round a proven lower bound upwards or render "at least less than 0.1".
        if value > 0, value < 0.1 {
            return value.formatted(.number.precision(.significantDigits(1...3)).rounded(rule: .towardZero))
        }
        return value.formatted(.number.precision(.fractionLength(0...1)).rounded(rule: .towardZero))
    }
}

/// Exact progress is available only when every saved component has fibre data.
/// A lower-bound subtotal is useful information, not an exact remaining allowance.
struct FibreSummaryRow: View {
    let summary: FibreIntakeSummary?
    var target: Double?
    var showsTarget = false

    var body: some View {
        let display = FibreSummaryPresentation(summary: summary)
        if showsTarget, let exact = display.exactGrams {
            NutritionProgressRow(title: "纤维目标", current: exact, target: target, unit: "g", metric: .fibre)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("纤维", value: display.amountText)
                    .contentTransition(.numericText())
                if showsTarget {
                    if let target {
                        Text("最低目标 \(FibreSummaryPresentation.formatted(target)) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未设置纤维目标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = display.detailText {
                    Label(detail, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
