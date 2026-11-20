import Foundation
import Combine

final class DataStore: ObservableObject {
    @Published var categories: [Category]
    @Published var paymentMethods: [PaymentMethod]
    @Published var records: [Transaction]

    private let fileURL: URL

    init() {
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = documentDir.appendingPathComponent("ledger_data.json")

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppData.self, from: data)
            categories = decoded.categories
            paymentMethods = decoded.paymentMethods
            records = decoded.records
        } catch {
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

    // MARK: 恢复默认
    func resetToDefaults() {
        categories = Category.builtInExpense + Category.builtInIncome
        paymentMethods = PaymentMethod.builtIn
        persist()
    }
}
