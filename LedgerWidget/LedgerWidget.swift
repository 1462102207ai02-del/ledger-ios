import WidgetKit
import SwiftUI
import Foundation

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
                               recentName: "", recentAmount: 0, recentIsExpense: true, hasRecent: false)
        }
        let cal = Calendar.current
        let now = Date()
        let today = data.records.filter { cal.isDateInToday($0.date) }
        let month = data.records.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        let sum = { (items: [Transaction], type: RecordType) in
            items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
        }
        let recent = data.records.max { $0.date < $1.date }
        return LedgerEntry(
            date: now,
            todayExpense: sum(today, .expense),
            todayIncome: sum(today, .income),
            monthExpense: sum(month, .expense),
            monthIncome: sum(month, .income),
            recentName: recent?.categoryName ?? "",
            recentAmount: recent?.amount ?? 0,
            recentIsExpense: recent?.type == .expense,
            hasRecent: recent != nil
        )
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
        VStack(alignment: .leading, spacing: 6) {
            Text("今日").font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(netTitle).font(.caption).foregroundColor(.secondary)
                Text(money(abs(entry.todayNet)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(netColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            HStack(spacing: 10) {
                Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
            }
            .font(.caption2)
            .lineLimit(1)
        }
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日").font(.caption).foregroundColor(.secondary)
                Text(netTitle).font(.caption2).foregroundColor(.secondary)
                Text(money(abs(entry.todayNet)))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(netColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                    Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近一笔").font(.caption2).foregroundColor(.secondary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("本月").font(.caption2).foregroundColor(.secondary)
                    Text("支 \(money(entry.monthExpense))  收 \(money(entry.monthIncome))")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日").font(.caption).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(netTitle).font(.subheadline).foregroundColor(.secondary)
                    Text(money(abs(entry.todayNet)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(netColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    Text("支出 \(money(entry.todayExpense))").foregroundColor(.red)
                    Text("收入 \(money(entry.todayIncome))").foregroundColor(.green)
                }
                .font(.caption)
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一笔").font(.caption).foregroundColor(.secondary)
                    if entry.hasRecent {
                        Text(entry.recentName).font(.headline).lineLimit(1)
                        Text((entry.recentIsExpense ? "-" : "+") + money(entry.recentAmount))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(entry.recentIsExpense ? .red : .green)
                    } else {
                        Text("暂无").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月").font(.caption).foregroundColor(.secondary)
                    Text("支出").font(.caption2).foregroundColor(.secondary)
                    Text(money(entry.monthExpense))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                    Text("收入").font(.caption2).foregroundColor(.secondary)
                    Text(money(entry.monthIncome))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        LedgerEntry(date: Date(), todayExpense: 88.5, todayIncome: 120,
                    monthExpense: 1560, monthIncome: 6800,
                    recentName: "午餐", recentAmount: 28, recentIsExpense: true, hasRecent: true)
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
        .description("今日收支、最近一笔与本月累计")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LedgerWidget()
    }
}
