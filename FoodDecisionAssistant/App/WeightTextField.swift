import SwiftUI

/// Keep raw input (including incomplete/invalid numbers) for validation and draft protection.
/// Only a new focus session moves the caret: subsequent taps and selection remain native.
struct WeightTextField: View {
    @Binding var text: String
    let isFocused: Bool

    @State private var selection: TextSelection?

    var body: some View {
        TextField("请输入", text: $text, selection: $selection)
            .keyboardType(.decimalPad)
            .onChange(of: isFocused) {
                if isFocused {
                    selection = TextSelection(insertionPoint: text.endIndex)
                } else {
                    // A String.Index from the previous value must not survive a new edit session.
                    selection = nil
                }
            }
    }
}
