import FoodDecisionCore
import Testing

@testable import FoodDecisionAssistant

struct GoalDatePresentationTests {
    struct Example: Sendable {
        let dayKey: Int
        let referenceKey: Int?
        let expected: String
    }

    @Test("Civil dates use Chinese month/day and retain the year when needed", arguments: [
        Example(dayKey: 20261012, referenceKey: 20261011, expected: "10月12日"),
        Example(dayKey: 20270101, referenceKey: 20261231, expected: "2027年1月1日"),
        Example(dayKey: 20251231, referenceKey: 20261011, expected: "2025年12月31日"),
        Example(dayKey: 20240229, referenceKey: 20240101, expected: "2月29日"),
        Example(dayKey: 20240229, referenceKey: 20260101, expected: "2024年2月29日"),
        Example(dayKey: 20261101, referenceKey: nil, expected: "2026年11月1日"),
    ])
    func chineseCivilDate(example: Example) throws {
        let day = try GoalDay(key: example.dayKey)
        let reference = try example.referenceKey.map { try GoalDay(key: $0) }
        #expect(GoalDatePresentation.text(for: day, referenceDay: reference) == example.expected)
    }
}
