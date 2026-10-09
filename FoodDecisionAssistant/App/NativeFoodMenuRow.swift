import Foundation
import SwiftUI

/// Large accessibility text is shown outside the compact menu's selected-value
/// label. Both presentations use the same native Picker binding and options.
struct NativeFoodMenuRow<Options: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var selection: UUID?

    private let selectedName: String
    private let identifier: String
    private let options: () -> Options

    init(
        selection: Binding<UUID?>,
        selectedName: String,
        identifier: String,
        @ViewBuilder options: @escaping () -> Options
    ) {
        _selection = selection
        self.selectedName = selectedName
        self.identifier = identifier
        self.options = options
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("食物")
                    .accessibilityHidden(true)

                Menu {
                    Picker("食物", selection: $selection, content: options)
                        .pickerStyle(.inline)
                } label: {
                    HStack {
                        Text(selectedName)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("食物")
                .accessibilityValue(selectedName)
                .accessibilityIdentifier(identifier)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("食物", selection: $selection, content: options)
                .pickerStyle(.menu)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }
}
