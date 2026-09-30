import Foundation

public enum SupplementRuleEngine {
    private static let prohibitedTerms = [
        "vitamin a",
        "retinol",
        "retinyl palmitate",
        "retinyl acetate",
        "cod liver oil",
        "维生素a",
        "维生素 a",
        "视黄醇",
        "鱼肝油",
    ]

    public static func assess(labelText: String, ruleVersion: String = "supplement-v1") -> Assessment {
        let normalized = labelText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if let term = prohibitedTerms.first(where: { normalized.localizedCaseInsensitiveContains($0) }) {
            return Assessment(
                conclusion: .prohibited,
                reasons: ["标签中发现维生素 A 相关成分：\(term)"],
                ruleVersion: ruleVersion
            )
        }

        if normalized.localizedCaseInsensitiveContains("beta-carotene") ||
            normalized.localizedCaseInsensitiveContains("β-carotene") ||
            normalized.localizedCaseInsensitiveContains("β-胡萝卜素") ||
            normalized.localizedCaseInsensitiveContains("胡萝卜素") {
            return Assessment(
                conclusion: .consultPharmacist,
                reasons: ["发现 β-胡萝卜素但未明确标注维生素 A，需要药师确认"],
                ruleVersion: ruleVersion
            )
        }

        return Assessment(
            conclusion: .consultPharmacist,
            reasons: ["药师确认前，补剂不显示“未发现冲突”"],
            ruleVersion: ruleVersion
        )
    }
}

