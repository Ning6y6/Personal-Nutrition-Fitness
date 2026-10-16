import FoodDecisionCore
import SwiftUI

/// UI-only state: never stored on a meal or written to its database.
struct InlineMealExpansionState: Equatable, Sendable {
    private(set) var expandedMealID: UUID?

    init(expandedMealID: UUID? = nil) {
        self.expandedMealID = expandedMealID
    }

    mutating func toggle(_ id: UUID) {
        expandedMealID = expandedMealID == id ? nil : id
    }

    mutating func prune(visibleIDs: [UUID]) {
        if let expandedMealID, !visibleIDs.contains(expandedMealID) { collapse() }
    }

    mutating func collapse() { expandedMealID = nil }
}

/// Reads historical snapshots only. Drafts and invalid records are never
/// promoted to confirmed data simply because a list row was expanded.
@MainActor
struct InlineMealPresentation {
    enum Status: Equatable, Sendable { case confirmed, draft, invalid }

    let status: Status
    let validatedMeal: MealLog?
    let energyText: String

    var canReuse: Bool { status == .confirmed && validatedMeal != nil }

    init(meal: PersistentMealLog) {
        if meal.estimateEvidenceGradeRawValue == EstimateEvidenceGrade.d.rawValue {
            status = .draft
            validatedMeal = nil
        } else {
            validatedMeal = try? meal.domainModel()
            status = validatedMeal == nil ? .invalid : .confirmed
        }
        energyText = KcalDisplay.amount(meal.energyKcal)
    }

    static func formattedSnapshotValue(_ value: Double, unit: String) -> String {
        guard value.isFinite, value >= 0 else { return "不可用" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}

struct MealExpandableRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let meal: PersistentMealLog
    let isExpanded: Bool
    var showsDate = false
    var showsActionsBeforeDetails = false
    var expansionScrollRequest: InlineMealScrollState.Request? = nil
    var onExpansionActionsLayout: (InlineMealScrollState.Request) -> Void = { _ in }
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onReuse: (MealLog) -> Void
    let onDetails: () -> Void

    var body: some View {
        let presentation = InlineMealPresentation(meal: meal)
        let laysOutLeadingActions = showsActionsBeforeDetails && isExpanded
        let layoutRequest = laysOutLeadingActions ? expansionScrollRequest : nil
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onToggle) {
                    MealSummaryRow(
                        meal: meal, showsDate: showsDate,
                        isExpanded: isExpanded, presentation: presentation
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("meal.row.\(meal.id.uuidString)")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "收起餐食摘要" : "展开食物分项、历史营养快照及操作")
                .id(Self.prefixScrollID(for: meal.id))

                if laysOutLeadingActions {
                    actions(canReuse: presentation.canReuse)
                        .font(.subheadline)
                        .id(Self.actionsScrollID(for: meal.id))
                        .onGeometryChange(for: InlineMealScrollState.Request?.self) { geometry in
                            // This newly inserted group has its own real layout;
                            // the unchanged collapsed summary cannot make it ready early.
                            geometry.size.height >= 44 ? layoutRequest : nil
                        } action: { request in
                            if let request { onExpansionActionsLayout(request) }
                        }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if presentation.status != .confirmed {
                        Label(
                            presentation.status == .draft
                                ? "未确认草稿：以下为原始快照，未计入正式汇总，不能复用。"
                                : "记录需修复：以下为原始快照，未计入正式汇总，不能复用。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.warningText)
                    }

                    ForEach(meal.components.sorted { $0.sortIndex < $1.sortIndex }) { component in
                        snapshotRow(
                            component.foodName.isEmpty ? "未命名分项" : component.foodName,
                            value: InlineMealPresentation.formattedSnapshotValue(
                                component.consumedWeightGrams, unit: component.unit
                            )
                        )
                    }
                    if meal.components.isEmpty {
                        Text("没有可显示的食物分项，请进入编辑检查。")
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    snapshotRow("热量", value: presentation.energyText)
                    snapshotRow("蛋白质", value: InlineMealPresentation.formattedSnapshotValue(meal.proteinGrams, unit: "g"))
                    snapshotRow("碳水", value: InlineMealPresentation.formattedSnapshotValue(meal.carbohydrateGrams, unit: "g"))
                    snapshotRow("脂肪", value: InlineMealPresentation.formattedSnapshotValue(meal.fatGrams, unit: "g"))
                    snapshotRow("饱和脂肪", value: InlineMealPresentation.formattedSnapshotValue(meal.saturatedFatGrams, unit: "g"))
                    if let validated = presentation.validatedMeal {
                        FibreSummaryRow(summary: try? FibreIntakeSummary(snapshots: validated.components.map(\.nutrients)))
                    } else {
                        snapshotRow(
                            "纤维（原始快照）",
                            value: meal.fibreGrams.map {
                                InlineMealPresentation.formattedSnapshotValue($0, unit: "g")
                            } ?? "未知"
                        )
                    }
                    if !showsActionsBeforeDetails {
                        actions(canReuse: presentation.canReuse)
                    }
                }
                .font(.subheadline)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func prefixScrollID(for mealID: UUID) -> String {
        "meal.prefix.\(mealID.uuidString)"
    }

    static func actionsScrollID(for mealID: UUID) -> String {
        "meal.actions.\(mealID.uuidString)"
    }

    @ViewBuilder
    private func snapshotRow(_ title: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(value).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actions(canReuse: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) { actionButtons(canReuse: canReuse) }
                .buttonStyle(.borderless)
        } else {
            HStack { actionButtons(canReuse: canReuse) }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func actionButtons(canReuse: Bool) -> some View {
        Button(action: onEdit) {
            Label("编辑", systemImage: "pencil")
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
            .accessibilityIdentifier("meal.edit.\(meal.id.uuidString)")
        Button(action: reuseMeal) {
            Label("复用", systemImage: "arrow.clockwise")
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
            .disabled(!canReuse)
            .accessibilityIdentifier("meal.reuse.\(meal.id.uuidString)")
            .accessibilityHint(canReuse ? "建立新的估算餐食，在保存前修改本次重量" : "未确认草稿或异常记录不能复用")
        Button(action: onDetails) {
            Label("查看详情", systemImage: "info.circle")
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
            .accessibilityIdentifier("meal.details.\(meal.id.uuidString)")
    }

    private func reuseMeal() {
        // Eligibility shown in the row is not a substitute for validation at
        // the action boundary. No source record or template is mutated here.
        guard meal.estimateEvidenceGradeRawValue != EstimateEvidenceGrade.d.rawValue,
              let validated = try? meal.domainModel() else { return }
        onReuse(validated)
    }
}
