import SwiftUI

@main
struct LedgerAppApp: App {
    @StateObject private var store = DataStore()
    @State private var showOCR = false
    @State private var showClipboardConfirm = false
    @State private var clipboardDraft = ClipboardOCR.Draft()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(showOCR: $showOCR)
                .environmentObject(store)
                .onAppear(perform: checkClipboardOnLaunch)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 从后台切回前台时再查一次，覆盖「复制后切回 App」的场景
                    checkClipboard(force: false)
                }
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "ledgerocr" { showOCR = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openOCR)) { _ in
                    showOCR = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .pasteboardOCR)) { _ in
                    // 手动点按「识别粘贴板内容」：绕过去重，直接检查
                    checkClipboard(force: true)
                }
                .sheet(isPresented: $showOCR) {
                    OCRImportView().environmentObject(store)
                }
                .sheet(isPresented: $showClipboardConfirm) {
                    ConfirmDraftView(seed: clipboardDraft).environmentObject(store)
                }
        }
    }

    /// 冷启动时检查粘贴板。用 UserDefaults 记住上次处理过的 changeCount，
    /// 避免同一段内容每次进首页都重复弹窗；同一 changeCount 只在首次处理。
    private func checkClipboardOnLaunch() {
        checkClipboard(force: false)
    }

    private func checkClipboard(force: Bool) {
        let pb = UIPasteboard.general
        let change = pb.changeCount
        let key = "ocr.lastPasteChange"
        // object(forKey:) 为 nil 表示从没记录过（此时 integer 默认为 0，不能据此判断，
        // 否则 changeCount 恰好为 0 的边界会被误判为「已处理」而跳过首次识别）。
        let hasRecord = UserDefaults.standard.object(forKey: key) != nil
        let last = UserDefaults.standard.integer(forKey: key)
        if !force && hasRecord && change == last { return }
        // 无论是否识别成功都记为已处理，避免反复打扰
        UserDefaults.standard.set(change, forKey: key)

        ClipboardOCR.read { draft in
            // 只要粘贴板有内容就弹窗：即使没识别出金额，也让用户手动填写并看到原文。
            guard draft.hadContent else { return }
            self.clipboardDraft = draft
            self.showClipboardConfirm = true
        }
    }
}

extension Notification.Name {
    static let openOCR = Notification.Name("openOCR")
    static let pasteboardOCR = Notification.Name("pasteboardOCR")
}

/// 处理主屏 3D Touch / 长按快捷菜单。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "com.mazexin.Bookkeeping.test.scan" {
            NotificationCenter.default.post(name: .openOCR, object: nil)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
