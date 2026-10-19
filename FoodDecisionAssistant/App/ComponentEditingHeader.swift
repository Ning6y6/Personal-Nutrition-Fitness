import SwiftUI

/// Keeps removal controls in the native Form editing mode, out of ordinary rows.
struct ComponentEditingHeader: View {
    let title: String
    let isEditing: Bool
    let identifier: String
    let toggleEditing: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Button(action: toggleEditing) {
                Text(isEditing ? "完成" : "编辑")
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .textCase(nil)
            .accessibilityHint(isEditing ? "收起分项删除控件" : "显示分项删除控件")
            .accessibilityIdentifier(identifier)
        }
    }
}
