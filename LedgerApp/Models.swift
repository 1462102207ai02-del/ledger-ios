import Foundation

// MARK: - 记录类型
enum RecordType: String, Codable, CaseIterable, Identifiable {
    case expense = "支出"
    case income = "收入"

    var id: String { rawValue }
}

// MARK: - 项目（支出项 / 收入项）
struct Category: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: RecordType
    var icon: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, type: RecordType, icon: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }

    static let builtInExpense: [Category] = [
        Category(name: "早餐", type: .expense, icon: "🥐", isBuiltIn: true),
        Category(name: "午餐", type: .expense, icon: "🍱", isBuiltIn: true),
        Category(name: "晚餐", type: .expense, icon: "🍚", isBuiltIn: true),
        Category(name: "宵夜", type: .expense, icon: "🍜", isBuiltIn: true),
        Category(name: "麻将", type: .expense, icon: "🎲", isBuiltIn: true),
        Category(name: "香烟", type: .expense, icon: "🚬", isBuiltIn: true),
        Category(name: "饮料", type: .expense, icon: "🥤", isBuiltIn: true),
        Category(name: "信用卡", type: .expense, icon: "💳", isBuiltIn: true),
        Category(name: "花呗", type: .expense, icon: "🌸", isBuiltIn: true),
        Category(name: "借呗", type: .expense, icon: "💸", isBuiltIn: true),
        Category(name: "京东白条", type: .expense, icon: "🛒", isBuiltIn: true),
        Category(name: "京东金条", type: .expense, icon: "🪙", isBuiltIn: true),
        Category(name: "分付", type: .expense, icon: "📲", isBuiltIn: true),
    ]

    static let builtInIncome: [Category] = [
        Category(name: "工资", type: .income, icon: "💰", isBuiltIn: true),
        Category(name: "货款", type: .income, icon: "📦", isBuiltIn: true),
    ]
}

// MARK: - 支付方式
struct PaymentMethod: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, icon: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }

    static let builtIn: [PaymentMethod] = [
        PaymentMethod(name: "微信", icon: "💬", isBuiltIn: true),
        PaymentMethod(name: "支付宝", icon: "🅰️", isBuiltIn: true),
        PaymentMethod(name: "银行卡", icon: "💳", isBuiltIn: true),
        PaymentMethod(name: "现金", icon: "💵", isBuiltIn: true),
    ]
}

// MARK: - 一笔账
struct Transaction: Codable, Identifiable, Hashable {
    var id: UUID
    var type: RecordType
    var categoryName: String
    var amount: Double
    var paymentMethodName: String
    var date: Date
    var note: String

    init(id: UUID = UUID(), type: RecordType, categoryName: String, amount: Double,
         paymentMethodName: String, date: Date = Date(), note: String = "") {
        self.id = id
        self.type = type
        self.categoryName = categoryName
        self.amount = amount
        self.paymentMethodName = paymentMethodName
        self.date = date
        self.note = note
    }
}

// MARK: - 整体持久化结构
struct AppData: Codable {
    var categories: [Category]
    var paymentMethods: [PaymentMethod]
    var records: [Transaction]
}
