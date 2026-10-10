import Foundation

public enum GoalHistoryError: Error, Sendable, Equatable, LocalizedError {
    case invalidDay(Int)
    case invalidTimeZoneIdentifier(String)
    case unavailableDay(Int, String)
    case unsupportedPolicyVersion(Int)
    case duplicateVersionID(UUID)
    case duplicateCommitSequence(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDay: "目标生效日期无效。"
        case .invalidTimeZoneIdentifier: "目标日期的时区无效。"
        case .unavailableDay: "该生效日期在所选时区不存在，请重新选择日期。"
        case .unsupportedPolicyVersion: "目标版本使用了尚不支持的选版规则。"
        case .duplicateVersionID: "目标历史存在重复标识，未选择任何版本。"
        case .duplicateCommitSequence: "目标历史存在重复提交序号，未选择任何版本。"
        }
    }
}
