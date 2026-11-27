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

        case .empty:
            break
        }
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
            // 账本变化后请系统刷新桌面/负一屏小组件
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[快捷记账] 数据保存失败: \(error.localizedDescription)")
            dataWarning = "账本保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: 记录
    func addRecord(_ record: Transaction) {
        records.append(record)
        persist()
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
    func addCategory(name: String, type: RecordType, icon: String = "🧾") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories.append(Category(name: trimmed, type: type, icon: icon))
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
    func addPaymentMethod(name: String, icon: String = "💳") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        paymentMethods.append(PaymentMethod(name: trimmed, icon: icon))
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
