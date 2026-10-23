import SwiftUI

/// Shared appearance only: each caller retains its native Button or NavigationLink behavior.
struct SettingsEntryLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let showsDisclosure: Bool

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(DesignTokens.accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}
