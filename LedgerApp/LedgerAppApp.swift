import SwiftUI

@main
struct LedgerAppApp: App {
    @StateObject private var store = DataStore()
    @State private var showOCR = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(showOCR: $showOCR)
                .environmentObject(store)
                .onOpenURL { url in
                    // ledgerocr://recognize —— 分享扩展 / 快捷指令拉起识别页
                    if url.scheme?.lowercased() == "ledgerocr" {
                        showOCR = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openOCR)) { _ in
                    // 3D Touch 菜单点击
                    showOCR = true
                }
                .sheet(isPresented: $showOCR) {
                    OCRImportView().environmentObject(store)
                }
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
