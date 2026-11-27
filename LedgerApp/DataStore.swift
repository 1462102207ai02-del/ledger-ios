import Foundation
import Combine
import WidgetKit

final class DataStore: ObservableObject {
    @Published var categories: [Category]
    @Published var paymentMethods: [PaymentMethod]
    @Published var records: [Transaction]
    /// 数据异常提示（损坏文件已备份、写入失败等），设置页会展示。
    @Published var dataWarning: String?

    private let fileURL: URL

    init() {
        fileURL = SharedStorage.activeFileURL

        // 先给全套默认值，保证 Swift 的初始化检查在任何分支都通过。
        categories = Category.builtInExpense + Category.builtInIncome
        paymentMethods = PaymentMethod.builtIn
        records = []
        dataWarning = nil

        var canPushSnapshot = true
        switch SharedStorage.loadResult() {
        case .success(let decoded):
            categories = decoded.categories
            paymentMethods = decoded.paymentMethods
            records = decoded.records

            // 旧格式或数据仍在旧路径：静默升级/迁移写回新结构，账目一条不丢。
            let needsUpgrade = decoded.schemaVersion < AppData.currentSchemaVersion
            let needsMigration: Bool = {
                guard let shared = SharedStorage.sharedFileURL else { return false }
                return !FileManager.default.fileExists(atPath: shared.path)
            }()
            if needsUpgrade || needsMigration {
                try? SharedStorage.write(AppData(categories: categories,
                                                 paymentMethods: paymentMethods,
                                                 records: records))
            }

        case .corrupt(let url):
            // 关键：先留底再回退。旧版本在这里直接清空，等于把账本弄丢。
            SharedStorage.backupCorruptFile(at: url)
            dataWarning = "账本文件无法读取，已自动备份原文件。当前是空白账本，请到「设置 → 导入账本」恢复备份后再继续记账。"
            // 不覆盖上一次的快照，避免小组件在用户恢复数据前被刷成空白。
            canPushSnapshot = false

        case .empty:
            break
        }

        // 冷启动也推一份快照：用户还没记过账时，小组件同样有可用数据。
        if canPushSnapshot { pushWidgetSnapshot() }
    }

    var dataFileDescription: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber else { return "暂无账本文件" }
        return String(format: "%.1f KB", size.doubleValue / 1024)
    }

    private func persist() {
        let snapshot = AppData(categories: categories, paymentMethods: paymentMethods, records: records)
        do {
            try SharedStorage.write(snapshot)
            dataWarning = nil
            // 共享容器之外再推一份 Keychain 快照：没有 App Group 时小组件靠它显示数据。
            pushWidgetSnapshot(from: snapshot)
            // 账本变化后请系统刷新桌面/负一屏小组件
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[快捷记账] 数据保存失败: \(error.localizedDescription)")
            dataWarning = "账本保存失败：\(error.localizedDescription)"
        }
    }

    private func pushWidgetSnapshot(from snapshot: AppData? = nil) {
        let source = snapshot ?? AppData(categories: categories,
                                         paymentMethods: paymentMethods,
                                         records: records)
        WidgetBridge.write(WidgetSnapshotBuilder.make(from: source))
    }

    // MARK: 记录
    func addRecord(_ record: Transaction) {
        records.append(record)
        persist()
    }

    /// 把记账弹窗里现场输入的自定义项目收编进对应分组。
    /// 只改内存、不单独写盘：调用方紧接着 addRecord / updateRecord 会触发一次 persist，
    /// 于是「保存账单」和「新增项目」是同一次落库；取消记账不会留下孤立项目。
    /// 已存在的同名项目自动跳过，天然去重；项目归属按当前账单的收支类型区分。
    func absorbCustomSelections(categoryName: String, type: RecordType,
                                paymentName: String) {
        let c = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = paymentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty && !categories.contains(where: { $0.type == type && $0.name == c }) {
            categories.append(Category(name: c, type: type))
        }
        if !p.isEmpty && !paymentMethods.contains(where: { $0.name == p }) {
            paymentMethods.append(PaymentMethod(name: p))
        }
    }

    func deleteRecord(_ record: Transaction) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func updateRecord(_ record: Transaction) {
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx] = record
        persist()
    }

    // MARK: 项目
    func addCategory(name: String, type: RecordType) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories.append(Category(name: trimmed, type: type))
        persist()
    }

    func deleteCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }
        persist()
    }

    /// 重命名项目，并同步更新以名称存储的历史账目，避免统计被拆成新旧两项。
    func renameCategory(_ category: Category, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 查重只在同类型内比较：支出和收入允许各自叫「其他」。
        guard !categories.contains(where: {
            $0.id != category.id && $0.type == category.type && $0.name == trimmed
        }) else { return }
        let oldName = category.name
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx].name = trimmed
        for i in records.indices
        where records[i].type == category.type && records[i].categoryName == oldName {
            records[i].categoryName = trimmed
        }
        persist()
    }

    // MARK: 支付方式
    func addPaymentMethod(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        paymentMethods.append(PaymentMethod(name: trimmed))
        persist()
    }

    func deletePaymentMethod(_ method: PaymentMethod) {
        paymentMethods.removeAll { $0.id == method.id }
        persist()
    }

    /// 重命名支付方式，并同步更新以名称存储的历史账目。
    func renamePaymentMethod(_ method: PaymentMethod, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !paymentMethods.contains(where: { $0.id != method.id && $0.name == trimmed }) else { return }
        let oldName = method.name
        guard let idx = paymentMethods.firstIndex(where: { $0.id == method.id }) else { return }
        paymentMethods[idx].name = trimmed
        for i in records.indices where records[i].paymentMethodName == oldName {
            records[i].paymentMethodName = trimmed
        }
        persist()
    }

    // MARK: 恢复默认
    func resetToDefaults() {
        categories = Category.builtInExpense + Category.builtInIncome
        paymentMethods = PaymentMethod.builtIn
        persist()
    }

    // MARK: 导出 / 导入
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(AppData(categories: categories,
                                          paymentMethods: paymentMethods,
                                          records: records))
    }

    /// 导入会整体替换当前账本；覆盖前自动留一份备份。
    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        SharedStorage.backupCurrentFile()
        categories = decoded.categories
        paymentMethods = decoded.paymentMethods
        records = decoded.records
        persist()
    }
}
