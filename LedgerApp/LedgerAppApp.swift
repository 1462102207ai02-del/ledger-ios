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
                .sheet(isPresented: $showOCR) {
                    OCRImportView().environmentObject(store)
                }
                .sheet(isPresented: $showClipboardConfirm) {
                    ConfirmDraftView(seed: clipboardDraft).environmentObject(store)
                }
        }
    }

    /// 冷启动时检查粘贴板。用 UserDefaults 记住上次识别到的 changeCount，
    /// 避免同一段内容每次进首页都重复弹窗；同一 changeCount 只在首次弹出。
    private func checkClipboardOnLaunch() {
        checkClipboard(force: false)
    }

    private func checkClipboard(force: Bool) {
        let pb = UIPasteboard.general
        let change = pb.changeCount
        let last = UserDefaults.standard.integer(forKey: "ocr.lastPasteChange")
        if !force && change == last { return }
        // 无论是否识别成功都记为已处理，避免反复打扰
        UserDefaults.standard.set(change, forKey: "ocr.lastPasteChange")

        ClipboardOCR.read { draft in
            guard !draft.isEmpty else { return }
            self.clipboardDraft = draft
            self.showClipboardConfirm = true
        }
    }
}

extension Notification.Name {
    static let openOCR = Notification.Name("openOCR")
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
