import Foundation

/// 主 App 与小组件共享的数据通道。
/// 两个 target 都会编译本文件，因此此处只依赖 Foundation。
enum SharedStorage {
    /// 旧包 / 无描述文件时的回退值。注意：这个值不再写入二进制签名。
    static let legacyAppGroupID = "group.com.mazexin.Bookkeeping"

    /// 运行时优先读取重签 profile 实际授权的 App Group。
    /// 签名里保持干净（不含受限 entitlement），因此这里必须能适配任意 group 名。
    static var resolvedAppGroupID: String {
        EmbeddedProfile.appGroupID ?? legacyAppGroupID
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
    static func write(_ data: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: activeFileURL, options: .atomic)
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
