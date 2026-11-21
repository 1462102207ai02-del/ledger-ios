import WidgetKit
import SwiftUI
import Foundation

// MARK: - 最近记录条目
struct RecentItem: Identifiable {
    let id: UUID
    let name: String
    let amount: Double
    let isExpense: Bool
    let timeText: String
}

// MARK: - 时间线数据
struct LedgerEntry: TimelineEntry {
    let date: Date
    let todayExpense: Double
    let todayIncome: Double
    let monthExpense: Double
    let monthIncome: Double
    let recentName: String
    let recentAmount: Double
    let recentIsExpense: Bool
    let hasRecent: Bool
    let recentItems: [RecentItem]

    var todayNet: Double { todayIncome - todayExpense }
    var monthNet: Double { monthIncome - monthExpense }
}

// MARK: - Provider
struct LedgerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerEntry {
        .demo
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerEntry>) -> Void) {
        let entry = loadEntry()
        // 系统在此时间后请求下一帧；App 内记一笔也会主动触发刷新
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> LedgerEntry {
        guard let data = SharedStorage.load() else {
            return LedgerEntry(date: Date(), todayExpense: 0, todayIncome: 0,
                               monthExpense: 0, monthIncome: 0,
                               recentName: "", recentAmount: 0, recentIsExpense: true,
                               hasRecent: false, recentItems: [])
        }
        let cal = Calendar.current
        let now = Date()
        let today = data.records.filter { cal.isDateInToday($0.date) }
        let month = data.records.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        let sum = { (items: [Transaction], type: RecordType) in
            items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
        }
        let recent = data.records.max { $0.date < $1.date }
        let recentItems = data.records
            .sorted { $0.date > $1.date }
            .prefix(9)
            .map { r in
                RecentItem(id: r.id, name: r.categoryName, amount: r.amount,
                           isExpense: r.type == .expense, timeText: shortTime(r.date))
            }
        return LedgerEntry(
            date: now,
            todayExpense: sum(today, .expense),
            todayIncome: sum(today, .income),
            monthExpense: sum(month, .expense),
            monthIncome: sum(month, .income),
            recentName: recent?.categoryName ?? "",
            recentAmount: recent?.amount ?? 0,
            recentIsExpense: recent?.type == .expense,
            hasRecent: recent != nil,
            recentItems: recentItems
        )
    }

    private func shortTime(_ date: Date) -> String {
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

// MARK: - 小组件视图
struct LedgerWidgetView: View {
    var entry: LedgerProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    // 今日大字：净额，正数绿“总收入”，负数红“总支出”
    private var netTitle: String { entry.todayNet >= 0 ? "总收入" : "总支出" }
    private var netColor: Color { entry.todayNet >= 0 ? .green : .red }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("今日").font(.caption).foregroundColor(.secondary)
                Text(netTitle).font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 2)
            Text(money(abs(entry.todayNet)))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundColor(netColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
            }
            .font(.caption2)
            .lineLimit(1)
        }
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日").font(.caption2).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(netTitle).font(.caption2).foregroundColor(.secondary)
                    Text(money(abs(entry.todayNet)))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(netColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                    Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
                }
                .font(.caption2)
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("最近一笔").font(.caption2).foregroundColor(.secondary)
                        Spacer(minLength: 2)
                        if entry.hasRecent, let first = entry.recentItems.first {
                            Text(first.timeText).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if entry.hasRecent {
                        Text(entry.recentName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text((entry.recentIsExpense ? "-" : "+") + money(entry.recentAmount))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(entry.recentIsExpense ? .red : .green)
                            .lineLimit(1)
                    } else {
                        Text("暂无").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("本月").font(.caption2).foregroundColor(.secondary)
                    Text("支出 \(money(entry.monthExpense))")
                        .font(.caption2).foregroundColor(.red)
                    Text("收入 \(money(entry.monthIncome))")
                        .font(.caption2).foregroundColor(.green)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 今日汇总
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日").font(.caption).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        Text("本月").foregroundColor(.secondary)
                        Text("支 \(money(entry.monthExpense))").foregroundColor(.red)
                        Text("收 \(money(entry.monthIncome))").foregroundColor(.green)
                    }
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(netTitle).font(.subheadline).foregroundColor(.secondary)
                    Text(money(abs(entry.todayNet)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(netColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("支 \(money(entry.todayExpense))  收 \(money(entry.todayIncome))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Divider()
            // 最近记录
            Text("最近记录").font(.caption).foregroundColor(.secondary)
            VStack(spacing: 0) {
                if entry.recentItems.isEmpty {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Text("暂无记录").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer(minLength: 0)
                } else {
                    ForEach(entry.recentItems) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(item.timeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 4)
                            Text((item.isExpense ? "-" : "+") + money(item.amount))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(item.isExpense ? .red : .green)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                        if item.id != entry.recentItems.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding()
    }

    private func money(_ v: Double) -> String {
        String(format: "¥%.2f", v)
    }
}

extension LedgerEntry {
    static var demo: LedgerEntry {
        let now = Date()
        let items = [
            RecentItem(id: UUID(), name: "跑腿", amount: 30, isExpense: true, timeText: "11:20"),
            RecentItem(id: UUID(), name: "午餐", amount: 28, isExpense: true, timeText: "12:05"),
            RecentItem(id: UUID(), name: "工资", amount: 170, isExpense: false, timeText: "10:30"),
            RecentItem(id: UUID(), name: "早餐", amount: 8.5, isExpense: true, timeText: "昨天"),
            RecentItem(id: UUID(), name: "香烟", amount: 25, isExpense: true, timeText: "昨天"),
            RecentItem(id: UUID(), name: "超市", amount: 62.3, isExpense: true, timeText: "11/19"),
            RecentItem(id: UUID(), name: "饮料", amount: 6, isExpense: true, timeText: "11/18"),
            RecentItem(id: UUID(), name: "晚餐", amount: 45, isExpense: true, timeText: "11/18"),
            RecentItem(id: UUID(), name: "货款", amount: 200, isExpense: false, timeText: "11/17")
        ]
        return LedgerEntry(date: now, todayExpense: 88.5, todayIncome: 170,
                           monthExpense: 770.17, monthIncome: 170,
                           recentName: "跑腿", recentAmount: 30, recentIsExpense: true,
                           hasRecent: true, recentItems: items)
    }
}

// MARK: - Widget 定义
struct LedgerWidget: Widget {
    let kind = "LedgerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerProvider()) { entry in
            LedgerWidgetView(entry: entry)
        }
        .configurationDisplayName("快捷记账")
        .description("今日收支、最近记录与本月累计")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LedgerWidget()
    }
}
