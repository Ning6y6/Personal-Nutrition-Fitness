/// Recorded-intake availability is separate from the mathematical sum of its values.
/// In particular, an empty sum of zero is not evidence of a user's actual zero intake.
enum MealIntakeAvailability: Equatable, Sendable {
    case noRecords
    case noConfirmedRecords
    case available
    case unavailable

    var canShowNutritionProgress: Bool { self == .available }

    var title: String {
        switch self {
        case .noRecords: "今日尚未记录"
        case .noConfirmedRecords: "今日记录尚不能计入合计"
        case .available: "今日已记录摄入"
        case .unavailable: "已记录摄入暂不可用"
        }
    }

    var explanation: String {
        switch self {
        case .noRecords:
            "尚未记录不代表摄入为 0。记录餐食后，再根据已记录数据计算进度。"
        case .noConfirmedRecords:
            "今日已有记录，但尚无可计入合计的已确认有效餐食。请检查未确认草稿或需修复的旧记录；未按 0 摄入计算。"
        case .available:
            "仅汇总已确认有效的餐食，不代表当天所有摄入都已记录。"
        case .unavailable:
            "已有正式餐食，但营养合计超出可安全计算范围。请到历史记录检查；未按 0 摄入计算。"
        }
    }

    var symbol: String {
        switch self {
        case .noRecords: "fork.knife.circle"
        case .noConfirmedRecords, .unavailable: "exclamationmark.triangle"
        case .available: "fork.knife"
        }
    }
}
