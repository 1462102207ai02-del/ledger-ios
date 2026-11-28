import Foundation

// MARK: - 记录类型
enum RecordType: String, Codable, CaseIterable, Identifiable {
    case expense = "支出"
    case income = "收入"

    var id: String { rawValue }
}

// MARK: - 收 / 付款渠道分组
/// 支出走「支付方式」，收入走「收款方式」，两组各自可自定义。
/// 账目里仍只有一个 paymentMethodName 字段（旧账本 / 旧导出 JSON 完全兼容），
/// 它按 type 解释为「付款渠道」或「收款渠道」，不需要为账目新增字段。
enum MethodGroup: String, Codable {
    case payment
    case receipt

    var title: String { self == .payment ? "支付方式" : "收款方式" }
    var recordType: RecordType { self == .payment ? .expense : .income }
    var systemImage: String { self == .payment ? "creditcard" : "tray.and.arrow.down" }
}

extension RecordType {
    var methodGroup: MethodGroup { self == .expense ? .payment : .receipt }
}

// MARK: - 项目（支出项 / 收入项）
// 说明：icon / isBuiltIn 是早期版本遗留字段，当前 UI 与逻辑都不再读取。
// 保留它们只为兼容已导出的账本 JSON —— 解码时多余键会被忽略、编码时仍会写出，
// 这样新旧版本互相导入都不会失败。项目不再携带任何图标。
struct Category: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: RecordType
    var icon: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, type: RecordType, icon: String = "", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }

    static let builtInExpense: [Category] = [
        Category(name: "早餐", type: .expense, isBuiltIn: true),
        Category(name: "午餐", type: .expense, isBuiltIn: true),
        Category(name: "晚餐", type: .expense, isBuiltIn: true),
        Category(name: "宵夜", type: .expense, isBuiltIn: true),
        Category(name: "麻将", type: .expense, isBuiltIn: true),
        Category(name: "香烟", type: .expense, isBuiltIn: true),
        Category(name: "饮料", type: .expense, isBuiltIn: true),
        Category(name: "信用卡", type: .expense, isBuiltIn: true),
        Category(name: "花呗", type: .expense, isBuiltIn: true),
        Category(name: "借呗", type: .expense, isBuiltIn: true),
        Category(name: "京东白条", type: .expense, isBuiltIn: true),
        Category(name: "京东金条", type: .expense, isBuiltIn: true),
        Category(name: "分付", type: .expense, isBuiltIn: true),
    ]

    static let builtInIncome: [Category] = [
        Category(name: "工资", type: .income, isBuiltIn: true),
        Category(name: "货款", type: .income, isBuiltIn: true),
    ]
}

// MARK: - 支付方式 / 收款方式
struct PaymentMethod: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, icon: String = "", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }

    static let builtIn: [PaymentMethod] = [
        PaymentMethod(name: "微信", isBuiltIn: true),
        PaymentMethod(name: "支付宝", isBuiltIn: true),
        PaymentMethod(name: "银行卡", isBuiltIn: true),
        PaymentMethod(name: "现金", isBuiltIn: true),
    ]

    /// 收款渠道与付款渠道是同一批，但属于独立分组：各自新建 UUID，
    /// 避免两组元素 Identifiable 撞车，也让用户可以分别增删改。
    static let builtInReceipt: [PaymentMethod] = [
        PaymentMethod(name: "微信", isBuiltIn: true),
        PaymentMethod(name: "支付宝", isBuiltIn: true),
        PaymentMethod(name: "银行卡", isBuiltIn: true),
        PaymentMethod(name: "现金", isBuiltIn: true),
    ]
}

// MARK: - 一笔账
/// amount 保留 Double 存储，与历史账本 JSON 完全兼容；
/// 所有求和与展示统一走 Money 的 Decimal 通道，避免浮点累加误差。
/// paymentMethodName 存渠道名，按 type 读作「支付方式」或「收款方式」。
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
    /// v2 起新增 receiptMethods（收款方式组）。旧账本没有这个键，由 DataStore 做一次性迁移。
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var categories: [Category]
    var paymentMethods: [PaymentMethod]
    var receiptMethods: [PaymentMethod]
    var records: [Transaction]

    /// 不给 receiptMethods 默认值：所有构造点必须显式传入，
    /// 漏改会在编译期报错，避免静默丢掉收款方式分组。
    init(schemaVersion: Int = AppData.currentSchemaVersion,
         categories: [Category],
         paymentMethods: [PaymentMethod],
         receiptMethods: [PaymentMethod],
         records: [Transaction]) {
        self.schemaVersion = schemaVersion
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.receiptMethods = receiptMethods
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, categories, paymentMethods, receiptMethods, records
    }

    /// 兼容旧账本：缺 schemaVersion 视为 0，缺任一数组视为空。
    /// receiptMethods 缺键时解码为空数组，由上层按 schemaVersion 判断是「待迁移」还是「用户主动清空」。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        paymentMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        receiptMethods = try c.decodeIfPresent([PaymentMethod].self, forKey: .receiptMethods) ?? []
        records = try c.decodeIfPresent([Transaction].self, forKey: .records) ?? []
    }
}

// MARK: - 小组件最近记录（主 App 与 Widget 共用）
struct RecentItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let amount: Double
    let isExpense: Bool
    let timeText: String
}
