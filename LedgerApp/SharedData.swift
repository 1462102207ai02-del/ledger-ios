import Foundation

/// 主 App 与小组件共享的数据通道。
/// 两个 target 都会编译本文件，因此此处不依赖 UIKit / WidgetKit。
enum SharedStorage {
    static let appGroupID = "group.com.mazexin.Bookkeeping"
    private static let fileName = "ledger_data.json"

    /// App Group 共享容器中的数据文件；App Group 不可用时返回 nil。
    static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// 旧版本的数据位置（迁移兼容用）。
    static var legacyFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent(fileName)
    }

    /// 读取账本：优先共享容器，读不到再回退旧路径，保证升级后旧账本不丢。
    static func load() -> AppData? {
        let decoder = JSONDecoder()
        if let url = sharedFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(AppData.self, from: data) {
            return decoded
        }
        if let data = try? Data(contentsOf: legacyFileURL),
           let decoded = try? decoder.decode(AppData.self, from: data) {
            return decoded
        }
        return nil
    }
}
