import Foundation

/// Display only. Stored nutrients, input text and policy comparisons retain their full precision.
enum KcalDisplay {
    static func value(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite, value >= 0 else { return "不可用" }
        if value > 0, value < 1 {
            return "不足 \(1.formatted(.number.locale(locale).precision(.fractionLength(0))))"
        }
        // Normalize negative zero and avoid an Int conversion for finite extreme values.
        let rounded = value == 0 ? 0 : value.rounded(.toNearestOrAwayFromZero)
        return rounded.formatted(.number.locale(locale).precision(.fractionLength(0)))
    }

    static func amount(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite, value >= 0 else { return "不可用" }
        return "\(self.value(value, locale: locale)) kcal"
    }
}
