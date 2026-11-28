import Foundation

/// 主 App 与小组件共享的数据通道。
/// 两个 target 都会编译本文件，因此此处只依赖 Foundation。
enum SharedStorage {
    /// 旧包 / 无描述文件时的回退值。注意：这个值不再写入二进制签名。
    static let legacyAppGroupID = "group.com.mazexin.Bookkeeping"

    /// 运行时探测「真正能用」的 App Group，而不是猜签名形态：
    ///  1) 主包（TrollStore 直装）签名里声明了内置 group，containerURL 对它有效；
    ///  2) 重签环境可能授权了 profile 里的另一个 group，内置不可用时就用它；
    ///  3) 都不可用时回退内置值，containerURL 返回 nil，数据落到旧 Documents 路径，功能不受影响。
    /// 用 containerURL 实测而不是只看描述文件，避免「profile 写了、系统却不认」的失配。
    static var resolvedAppGroupID: String {
        let fm = FileManager.default
        for candidate in candidateGroupIDs {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
                return candidate
            }
        }
        return legacyAppGroupID
    }

    private static var candidateGroupIDs: [String] {
        var ids = [legacyAppGroupID]
        if let profile = EmbeddedProfile.appGroupID, !ids.contains(profile) {
            ids.append(profile)
        }
        return ids
    }

    private static let fileName = "ledger_data.json"

    /// App Group 共享容器中的数据文件；App Group 不可用时返回 nil。
    static var sharedFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroupID)?
            .appendingPathComponent(fileName)
    }

    /// 旧版本的数据位置（迁移兼容用）。
    static var legacyFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent(fileName)
    }

    /// 实际生效的数据文件位置，所有写入统一落这里。
    static var activeFileURL: URL { sharedFileURL ?? legacyFileURL }

    private static var candidateURLs: [URL] {
        var urls: [URL] = []
        if let shared = sharedFileURL { urls.append(shared) }
        urls.append(legacyFileURL)
        return urls
    }

    enum LoadResult {
        case success(AppData)
        case corrupt(URL)
        case empty
    }

    /// 依次尝试共享容器与旧路径，任一可读且可解码即返回。
    /// 文件存在但全都解不开时返回 .corrupt，由上层备份并告警，绝不静默清空。
    static func loadResult() -> LoadResult {
        let decoder = JSONDecoder()
        var firstCorrupt: URL?
        for url in candidateURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let decoded = try? decoder.decode(AppData.self, from: data) {
                return .success(decoded)
            }
            if firstCorrupt == nil { firstCorrupt = url }
        }
        if let bad = firstCorrupt { return .corrupt(bad) }
        return .empty
    }

    /// 小组件读取入口：依次尝试共享容器与旧路径，读不到返回 nil。
    static func load() -> AppData? {
        if case .success(let data) = loadResult() { return data }
        return nil
    }

    /// 原子写入当前账本。
    /// App Group 可用时（TrollStore 主包）同时写共享容器与旧 Documents 路径：
    ///  - 共享容器给小组件读，这是主通道；
    ///  - 旧路径留一份，签名/授权变化时账本仍能被 loadResult() 找到并迁移，不会丢。
    /// 旧路径写失败不影响共享容器，小组件照常可用。
    static func write(_ data: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        let primary = activeFileURL
        try encoded.write(to: primary, options: .atomic)
        if primary.path != legacyFileURL.path {
            try? encoded.write(to: legacyFileURL, options: .atomic)
        }
    }

    // MARK: - 备份

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    /// 把损坏文件另存，避免下次启动被原子写覆盖后彻底丢失。
    @discardableResult
    static func backupCorruptFile(at url: URL) -> URL? {
        backupFile(at: url, suffix: "corrupt")
    }

    /// 导入/覆盖前留一份当前账本。
    @discardableResult
    static func backupCurrentFile() -> URL? {
        backupFile(at: activeFileURL, suffix: "backup")
    }

    private static func backupFile(at url: URL, suffix: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("ledger_data.\(suffix)-\(stamp()).json")
        guard !fm.fileExists(atPath: dest.path) else { return nil }
        try? fm.copyItem(at: url, to: dest)
        return dest
    }
}
