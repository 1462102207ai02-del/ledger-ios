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
/// amount 保留 Double 存储，与历史账本 JSON 完全兼容；
/// 所有求和与展示统一走 Money 的 Decimal 通道，避免浮点累加误差。
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

// MARK: - 金额工具（纯 Foundation，主 App 与 Widget 共用）
enum Money {
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(0)
    }

    static func sum(_ values: [Double]) -> Decimal {
        values.reduce(Decimal(0)) { $0 + decimal($1) }
    }

    static func sum(_ records: [Transaction], type: RecordType) -> Decimal {
        sum(records.filter { $0.type == type }.map { $0.amount })
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func string(_ value: Decimal, decimals: Int = 2) -> String {
        let number = NSDecimalNumber(decimal: value)
        let isNegative = number.compare(NSDecimalNumber(string: "0")) == .orderedAscending
        // 用十进制乘法取绝对值，不经过 Double，保持精确。
        let shown: NSNumber = isNegative
            ? number.multiplying(by: NSDecimalNumber(string: "-1"))
            : number

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "zh_CN")
        let text = formatter.string(from: shown) ?? "0.00"
        return (isNegative ? "-¥" : "¥") + text
    }

    static func string(_ value: Double, decimals: Int = 2) -> String {
        string(decimal(value), decimals: decimals)
    }
}

// MARK: - 整体持久化结构
struct AppData: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var categories: [Category]
    var paymentMethods: [PaymentMethod]
    var records: [Transaction]

    init(schemaVersion: Int = AppData.currentSchemaVersion,
         categories: [Category],
         paymentMethods: [PaymentMethod],
         records: [Transaction]) {
        self.schemaVersion = schemaVersion
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, categories, paymentMethods, records
    }

    /// 兼容旧账本：缺 schemaVersion 视为 0，缺任一数组视为空。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        records = try c.decodeIfPresent([Transaction].self, forKey: .records) ?? []
    }
}
