import Foundation
import Combine
import WidgetKit

final class DataStore: ObservableObject {
    @Published var categories: [Category]
    @Published var paymentMethods: [PaymentMethod]
    @Published var receiptMethods: [PaymentMethod]
    @Published var records: [Transaction]
    /// 数据异常提示（损坏文件已备份、写入失败等），设置页会展示。
    @Published var dataWarning: String?

    private let fileURL: URL

    init() {
        fileURL = SharedStorage.activeFileURL

        // 先给全套默认值，保证 Swift 的初始化检查在任何分支都通过。
        categories = Category.builtInExpense + Category.builtInIncome
        paymentMethods = PaymentMethod.builtIn
        receiptMethods = PaymentMethod.builtInReceipt
        records = []
        dataWarning = nil

        var canPushSnapshot = true
        switch SharedStorage.loadResult() {
        case .success(let decoded):
            categories = decoded.categories
            paymentMethods = decoded.paymentMethods
            receiptMethods = Self.migratedReceiptMethods(from: decoded)
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
                                                 receiptMethods: receiptMethods,
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

    /// v1 账本没有「收款方式」组。升级时给内置渠道，并把历史收入记录里出现过的渠道名补进来，
    /// 否则编辑一笔旧收入时会发现原来选的渠道不在可选项里。
    /// v2 且数组为空 = 用户自己删空了，尊重用户，不再自动补。
    private static func migratedReceiptMethods(from data: AppData) -> [PaymentMethod] {
        guard data.schemaVersion < AppData.currentSchemaVersion else { return data.receiptMethods }
        var result = PaymentMethod.builtInReceipt
        var seen = Set(result.map { $0.name })
        for record in data.records where record.type == .income {
            let name = record.paymentMethodName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(PaymentMethod(name: name))
        }
        return result
    }

    var dataFileDescription: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber else { return "暂无账本文件" }
        return String(format: "%.1f KB", size.doubleValue / 1024)
    }

    private var currentSnapshot: AppData {
        AppData(categories: categories,
                paymentMethods: paymentMethods,
                receiptMethods: receiptMethods,
                records: records)
    }

    private func persist() {
        let snapshot = currentSnapshot
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
        WidgetBridge.write(WidgetSnapshotBuilder.make(from: snapshot ?? currentSnapshot))
    }

    // MARK: 记录
    func addRecord(_ record: Transaction) {
        records.append(record)
        persist()
    }

    /// 把记账弹窗里现场输入的自定义名称收编进对应分组。
    /// 只改内存、不单独写盘：调用方紧接着 addRecord / updateRecord 会触发一次 persist，
    /// 于是「保存账单」和「新增项目」是同一次落库；取消记账不会留下孤立项目。
    /// 项目按收支类型归组，渠道按 type 归到支付方式 / 收款方式。
    func absorbCustomSelections(categoryName: String, type: RecordType,
                                methodName: String) {
        let c = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty && !categories.contains(where: { $0.type == type && $0.name == c }) {
            categories.append(Category(name: c, type: type))
        }
        absorbMethodName(methodName, for: type)
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

    // MARK: 支付方式 / 收款方式（同一套结构，按 MethodGroup 分流）
    func methodList(_ group: MethodGroup) -> [PaymentMethod] {
        group == .payment ? paymentMethods : receiptMethods
    }

    private func setMethodList(_ group: MethodGroup, _ list: [PaymentMethod]) {
        switch group {
        case .payment: paymentMethods = list
        case .receipt: receiptMethods = list
        }
    }

    /// 现场输入的渠道名收编到对应分组；已存在同名自动跳过。
    func absorbMethodName(_ raw: String, for type: RecordType) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = type.methodGroup
        var list = methodList(group)
        guard !list.contains(where: { $0.name == name }) else { return }
        list.append(PaymentMethod(name: name))
        setMethodList(group, list)
    }

    func addMethod(name: String, to group: MethodGroup) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = methodList(group)
        guard !list.contains(where: { $0.name == trimmed }) else { return }
        list.append(PaymentMethod(name: trimmed))
        setMethodList(group, list)
        persist()
    }

    func deleteMethod(_ method: PaymentMethod, from group: MethodGroup) {
        var list = methodList(group)
        list.removeAll { $0.id == method.id }
        setMethodList(group, list)
        persist()
    }

    /// 重命名渠道，只同步同方向的历史账目：
    /// 改「支付方式」里的微信，不该把收入记录里「收款方式：微信」一起改掉，反之亦然。
    func renameMethod(_ method: PaymentMethod, in group: MethodGroup, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = methodList(group)
        guard !list.contains(where: { $0.id != method.id && $0.name == trimmed }) else { return }
        guard let idx = list.firstIndex(where: { $0.id == method.id }) else { return }
        let oldName = list[idx].name
        list[idx].name = trimmed
        setMethodList(group, list)
        let targetType = group.recordType
        for i in records.indices
        where records[i].type == targetType && records[i].paymentMethodName == oldName {
            records[i].paymentMethodName = trimmed
        }
        persist()
    }

    // MARK: 恢复默认
    func resetToDefaults() {
        categories = Category.builtInExpense + Category.builtInIncome
        paymentMethods = PaymentMethod.builtIn
        receiptMethods = PaymentMethod.builtInReceipt
        persist()
    }

    // MARK: 导出 / 导入
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(currentSnapshot)
    }

    /// 导入会整体替换当前账本；覆盖前自动留一份备份。
    /// 旧版 JSON（无 receiptMethods）同样走迁移，历史收入渠道不会丢。
    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(AppData.self, from: data)
        SharedStorage.backupCurrentFile()
        categories = decoded.categories
        paymentMethods = decoded.paymentMethods
        receiptMethods = Self.migratedReceiptMethods(from: decoded)
        records = decoded.records
        persist()
    }
}
