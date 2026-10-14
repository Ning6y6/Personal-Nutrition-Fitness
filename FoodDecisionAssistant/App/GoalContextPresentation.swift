import FoodDecisionCore

/// Presentation only: the reader's selected current goal remains authoritative.
enum GoalContextPresentation {
    static let legacyCurrentText = "当前目标是在更新前设置的，过去的修改记录无法还原。"
    static let legacyNeedsConfirmationText = "之前的目标信息不完整或无法确定，请到预算与目标页重新确认。原记录会保留。"

    static func text(for snapshot: GoalHistorySnapshot, day: GoalDay, display: AppDateDisplayContext = .init()) -> String? {
        if snapshot.legacyNeedsConfirmation {
            return legacyNeedsConfirmationText
        }
        if let scheduledDay = snapshot.versions.lazy.map(\.effectiveDay).filter({ $0 > day }).min() {
            let date = GoalDatePresentation.text(for: scheduledDay, referenceDay: day, display: display)
            if snapshot.currentProfile != nil {
                return "新目标将于\(date)生效，今天仍使用当前目标。"
            }
            return "新目标将于\(date)生效，今天还没有生效的目标。"
        }
        if snapshot.selected == nil, snapshot.legacyCurrent != nil {
            return legacyCurrentText
        }
        return nil
    }
}
