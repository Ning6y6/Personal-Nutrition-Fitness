import SwiftUI

/// The focused form owns its completion action and reserves space for it.
/// This avoids depending on keyboard-toolbar registration across navigation.
struct FormKeyboardCompletion: ViewModifier {
    let isPresented: Bool
    let identifier: String
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if isPresented {
                HStack {
                    Spacer()
                    Button("完成", action: onComplete)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .accessibilityIdentifier(identifier)
                }
                .padding()
            }
        }
    }
}

extension View {
    func formKeyboardCompletion(
        isPresented: Bool,
        identifier: String,
        onComplete: @escaping () -> Void
    ) -> some View {
        modifier(FormKeyboardCompletion(
            isPresented: isPresented, identifier: identifier, onComplete: onComplete
        ))
    }
}
