import Foundation
import Combine

final class DataStore: ObservableObject {
    @Published var categories: [Category]
    @Published var paymentMethods: [PaymentMethod]
    @Published var records: [Transaction]

    private let fileURL: URL

    init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        fileURL = paths[0].appendingPathComponent("ledger_data.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: data) {
            categories = decoded.categories
            paymentMethods = decoded.paymentMethods
            records = decoded.records
        } else {
            categories = Category.builtInExpense + Category.builtInIncome
            paymentMethods = PaymentMethod.builtIn
            records = []
        }
    }

    private func persist() {
        let data = AppData(categories: categories, paymentMethods: paymentMethods, records: records)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
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
