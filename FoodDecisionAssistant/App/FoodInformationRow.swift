import SwiftUI

/// A wrapping label/value row remains readable at the largest accessibility sizes.
struct FoodInformationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(value)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent(title) {
                    Text(value)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
