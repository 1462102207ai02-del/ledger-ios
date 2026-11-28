import Foundation
import Security

/// 主 App 与小组件之间的数据快照（兜底通道）。
///
/// 主通道是 App Group 共享容器（见 SharedStorage）：TrollStore 主包在签名里声明了
/// group.com.mazexin.Bookkeeping，主 App 与 widget 读写同一个容器，数据最完整。
/// 早期版本把 App Group 从签名里移除后，TrollStore 下 containerURL 返回 nil，
/// 小组件只剩这条 Keychain 兜底；而纯 ad-hoc 签名又没有可用的共享 access group，
/// 于是两条通道同时断，小组件显示空态。
///
/// 现在恢复主包的 App Group 授权，Keychain 退居兜底。写入/读取/解码失败一律打日志，
/// 不再静默吞掉 —— 否则小组件空白时完全无法判断是哪一环断了。
struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var data: AppData
}

/// 主 App 与小组件共用的汇总计算，避免两边各写一份。
enum WidgetSnapshotBuilder {
    /// Keychain 单条不宜过大；最近 N 条足够覆盖今日/本月统计与「最近记录」列表。
    static let maxRecords = 150

    static func make(from source: AppData, now: Date = Date()) -> WidgetSnapshot {
        let records = Array(
            source.records.sorted { $0.date > $1.date }.prefix(maxRecords)
        )
        return WidgetSnapshot(
            updatedAt: now,
            data: AppData(categories: source.categories,
                          paymentMethods: source.paymentMethods,
                          receiptMethods: source.receiptMethods,
                          records: records)
        )
    }

    struct Summary {
        var todayExpense: Double
        var todayIncome: Double
        var monthExpense: Double
        var monthIncome: Double
        var recentItems: [RecentItem]
    }

    static func summary(from data: AppData, now: Date = Date()) -> Summary {
        let cal = Calendar.current
        let today = data.records.filter { cal.isDateInToday($0.date) }
        let month = data.records.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        // 求和走 Decimal，避免大量小额累加后的浮点误差。
        let sum = { (items: [Transaction], type: RecordType) -> Double in
            Money.double(Money.sum(items, type: type))
        }
        let recentItems = data.records
            .sorted { $0.date > $1.date }
            .prefix(13)
            .map { r in
                RecentItem(id: r.id, name: r.categoryName, amount: r.amount,
                           isExpense: r.type == .expense, timeText: shortTime(r.date))
            }
        return Summary(todayExpense: sum(today, .expense),
                       todayIncome: sum(today, .income),
                       monthExpense: sum(month, .expense),
                       monthIncome: sum(month, .income),
                       recentItems: recentItems)
    }

    private static func shortTime(_ date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "昨天"
        }
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }
}

// MARK: - Keychain 快照通道

enum WidgetBridge {
    private static let service = "com.mazexin.Bookkeeping.widget-snapshot"
    private static let account = "latest"

    /// 不显式指定 kSecAttrAccessGroup：让系统使用 entitlement 的默认 access group
    /// （多数自签 profile 为 `<TeamID>.*`，主 App 与 widget 相同，天然可跨进程共享）；
    /// 查询时不指定 group 也会搜索所有可访问组，比从描述文件硬解析更不易失配。
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            print("[快捷记账] Keychain 快照编码失败")
            return
        }
        let query = baseQuery()
        _ = SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        // errSecMissingEntitlement(-34018) 常见于无 keychain-access-groups 的 ad-hoc 签名。
        // 此时共享容器才是主通道，这里只留一条诊断信息，不影响账本落库。
        if status != errSecSuccess {
            print("[快捷记账] Keychain 快照写入失败 status=\(status)，由共享容器通道兜底")
        }
    }

    static func read() -> WidgetSnapshot? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            print("[快捷记账] Keychain 快照读取失败 status=\(status)")
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            print("[快捷记账] Keychain 快照解码失败: \(error)")
            return nil
        }
    }
}

// MARK: - 运行时描述文件解析

/// 不把 App Group ID 写死在签名里；改在运行时从 provisioning profile 读取。
/// Widget 的 appex 里可能没有描述文件，因此会向 containing app bundle 上溯查找。
enum EmbeddedProfile {
    private static let cached: [String: Any]? = loadEntitlements()

    static var entitlements: [String: Any]? { cached }

    static var appGroupID: String? {
        guard let entitlements = entitlements,
              let groups = entitlements["com.apple.security.application-groups"] as? [String],
              let first = groups.first, !first.isEmpty else { return nil }
        return first
    }

    private static func loadEntitlements() -> [String: Any]? {
        for url in candidateURLs {
            guard let data = try? Data(contentsOf: url),
                  let plist = extractPlist(from: data),
                  let dict = plist as? [String: Any],
                  let ent = dict["Entitlements"] as? [String: Any] else { continue }
            return ent
        }
        return nil
    }

    private static var candidateURLs: [URL] {
        var urls: [URL] = []
        if let own = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") {
            urls.append(own)
        }
        var current = Bundle.main.bundleURL
        for _ in 0..<4 {
            current = current.deletingLastPathComponent()
            let candidate = current.appendingPathComponent("embedded.mobileprovision")
            if FileManager.default.fileExists(atPath: candidate.path) {
                urls.append(candidate)
            }
        }
        return urls
    }

    /// mobileprovision 是 CMS 外壳包着明文 XML plist，截取 `<?xml ... </plist>` 即可解析。
    private static func extractPlist(from data: Data) -> Any? {
        let bytes = [UInt8](data)
        let startMarker = Array("<?xml".utf8)
        let endMarker = Array("</plist>".utf8)
        guard let start = index(of: startMarker, in: bytes, from: 0),
              let end = index(of: endMarker, in: bytes, from: start) else { return nil }
        let slice = Data(bytes[start..<(end + endMarker.count)])
        return try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)
    }

    private static func index(of pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !pattern.isEmpty, bytes.count - start >= pattern.count else { return nil }
        var i = start
        while i <= bytes.count - pattern.count {
            if bytes[i] == pattern[0] {
                var matched = true
                if pattern.count > 1 {
                    for j in 1..<pattern.count {
                        if bytes[i + j] != pattern[j] { matched = false; break }
                    }
                }
                if matched { return i }
            }
            i += 1
        }
        return nil
    }
}
