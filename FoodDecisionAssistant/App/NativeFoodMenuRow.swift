import SwiftUI

/// Opens the shared search page without binding navigation to a mutable row index.
struct NativeFoodMenuRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedName: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("食物")
                            .foregroundStyle(.primary)
                        selectedValue
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("食物")
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        selectedValue
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("食物")
        .accessibilityValue(selectedName)
        .accessibilityHint("打开本地食物搜索")
        .accessibilityIdentifier(identifier)
    }

    private var selectedValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(selectedName)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        .contentShape(.rect)
    }
}
