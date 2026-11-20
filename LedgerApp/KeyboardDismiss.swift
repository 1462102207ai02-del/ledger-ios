import SwiftUI

#if canImport(UIKit)
extension UIApplication {
    // 让当前第一响应者（键盘）放弃焦点，从而收起键盘
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

// 点击输入区域以外收起键盘，并在键盘上方提供「完成」按钮
private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.dismissKeyboard()
            }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("完成") {
                            UIApplication.shared.dismissKeyboard()
                        }
                    }
                }
            }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
