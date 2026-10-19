import Foundation

public enum FoodCatalogError: Error, Equatable, Sendable, LocalizedError {
    case missingResource
    case unsupportedVersion
    case invalidSource
    case insufficientFoods
    case duplicateIdentifier
    case duplicateSourceCode
    case invalidRecord(code: String)
    case inconsistentNutrient(code: String, field: String)

    public var errorDescription: String? {
        switch self {
        case .missingResource: "随附食物目录缺失，仍可使用本地已有食品。"
        case .unsupportedVersion: "食物目录版本无法识别，未修改已有数据。"
        case .invalidSource: "食物目录来源资料不完整，未修改已有数据。"
        case .insufficientFoods: "随附食物目录不完整，未修改已有数据。"
        case .duplicateIdentifier, .duplicateSourceCode: "食物目录包含重复标识，未修改已有数据。"
        case .invalidRecord, .inconsistentNutrient: "食物目录校验失败，未修改已有数据。"
        }
    }
}
