import SwiftUI
import UIKit

#if canImport(UIKit)

// MARK: - 键盘收起

extension UIApplication {
    /// 让当前第一响应者（输入框）放弃焦点，从而收起键盘。公开 API，无私有接口。
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// 键盘收起点击手势的回调目标。
private final class KeyboardTapTarget: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardTapTarget()

    /// 允许与其他手势（按钮点击、列表滚动）同时识别，选项按钮点击不会被吞掉。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    /// 点击输入框本身时不拦截，避免刚聚焦就被收起。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTextInput(touch.view)
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        UIApplication.shared.dismissKeyboard()
    }

    private func isTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView { return true }
            current = candidate.superview
        }
        return false
    }
}

/// 标记类型，用于避免重复安装手势。
private final class KeyboardDismissTapGesture: UITapGestureRecognizer {}

/// 点击输入框以外区域自动收起键盘。
/// 不用 SwiftUI 的 .onTapGesture 覆盖页面——那会抢占 Picker／Button 的点击。
private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }

            let installed = window.gestureRecognizers?.contains {
                $0 is KeyboardDismissTapGesture
            } ?? false
            guard !installed else { return }

            let tap = KeyboardDismissTapGesture(target: KeyboardTapTarget.shared,
                                                action: #selector(KeyboardTapTarget.handleTap(_:)))
            // 关键：不取消子视图的触摸，选项按钮／列表点击照常生效
            tap.cancelsTouchesInView = false
            tap.delegate = KeyboardTapTarget.shared
            window.addGestureRecognizer(tap)
        }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

#endif
