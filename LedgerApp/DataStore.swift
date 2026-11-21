import Foundation
import Combine
import WidgetKit

final class DataStore: ObservableObject {
    @Published var categories: [Category]
    @Published var paymentMethods: [PaymentMethod]
    @Published var records: [Transaction]

    private let fileURL: URL

    init() {
        // 写入统一落到共享容器（App Group 不可用则退回旧路径），保证小组件能读到同一份账本
        fileURL = SharedStorage.sharedFileURL ?? SharedStorage.legacyFileURL

        if let decoded = SharedStorage.load() {
            categories = decoded.categories
            paymentMethods = decoded.paymentMethods
            records = decoded.records
            // 若数据来自旧路径，立即迁移一份到共享容器（原子写，失败不影响原始数据）
            if let shared = SharedStorage.sharedFileURL,
               !FileManager.default.fileExists(atPath: shared.path) {
                persist()
            }
        } else {
            // 首次启动或数据损坏时回退到预置数据，不向外泄露细节
            categories = Category.builtInExpense + Category.builtInIncome
            paymentMethods = PaymentMethod.builtIn
            records = []
        }
    }

    private func persist() {
        let snapshot = AppData(categories: categories, paymentMethods: paymentMethods, records: records)
        do {
            let encoded = try JSONEncoder().encode(snapshot)
            try encoded.write(to: fileURL, options: .atomic)
            // 账本变化后请系统刷新桌面/负一屏小组件
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[快捷记账] 数据保存失败: \(error.localizedDescription)")
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
        guard !categories.contains(where: { $0.id != category.id && $0.name == trimmed }) else { return }
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
}
