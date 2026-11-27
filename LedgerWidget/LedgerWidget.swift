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
    let recentItems: [RecentItem]

    var todayNet: Double { todayIncome - todayExpense }
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
        let now = Date()
        let entry = loadEntry()
        let cal = Calendar.current

        // 「今日」必须在 0 点重算：把下一次刷新对齐到最近的午夜或 1 小时后，取更早者。
        let nextMidnight = cal.nextDate(after: now,
                                        matching: DateComponents(hour: 0, minute: 0, second: 0),
                                        matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
        let inOneHour = now.addingTimeInterval(3600)
        let next = min(nextMidnight, inOneHour)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> LedgerEntry {
        let now = Date()
        // 通道 1：共享容器里的完整账本（App Group 可用时优先，数据最完整）。
        if let data = SharedStorage.load() {
            return entry(from: data, now: now)
        }
        // 通道 2：主 App 写入的 Keychain 快照。
        // 剪贴板在 iOS 后台不可读（Apple 明确策略），所以兜底不能用 UIPasteboard。
        if let snapshot = WidgetBridge.read() {
            return entry(from: snapshot.data, now: now)
        }
        return LedgerEntry(date: now, todayExpense: 0, todayIncome: 0,
                           monthExpense: 0, monthIncome: 0, recentItems: [])
    }

    private func entry(from data: AppData, now: Date) -> LedgerEntry {
        let s = WidgetSnapshotBuilder.summary(from: data, now: now)
        return LedgerEntry(date: now,
                           todayExpense: s.todayExpense,
                           todayIncome: s.todayIncome,
                           monthExpense: s.monthExpense,
                           monthIncome: s.monthIncome,
                           recentItems: s.recentItems)
    }
}

// MARK: - 小组件视图
struct LedgerWidgetView: View {
    var entry: LedgerProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemLarge:
                largeView
            default:
                mediumView
            }
        }
        // 点组件任意位置直达「记一笔」，由主 App 的 onOpenURL 接住并聚焦金额。
        .widgetURL(URL(string: "ledger://add"))
    }

    // 今日大字：净额，正数绿「总收入」，负数红「总支出」
    private var netTitle: String { entry.todayNet >= 0 ? "总收入" : "总支出" }
    private var netColor: Color { entry.todayNet >= 0 ? .green : .red }

    private var addHint: some View {
        Image(systemName: "plus.circle.fill")
            .font(.caption)
            .foregroundColor(.accentColor)
    }

    private var smallView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0) // 上下对称 Spacer，确保内容块垂直居中
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("今日").font(.headline)
                    Spacer(minLength: 2)
                    addHint
                }
                Text(netTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(money(abs(entry.todayNet)))
                    .font(.system(size: 25, weight: .bold))
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            // 左：今日（大标题）+ 总支出（小标题）两行；金额垂直居中于左区
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("今日")
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 2)
                    addHint
                }
                Text(netTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(money(abs(entry.todayNet)))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(netColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .center) // 金额垂直居中
                HStack(spacing: 6) {
                    Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                    Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Divider()

            // 右：最近一笔 + 本月
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("最近一笔").font(.caption2).foregroundColor(.secondary)
                        Spacer(minLength: 2)
                        if let first = entry.recentItems.first {
                            Text(first.timeText).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if let first = entry.recentItems.first {
                        Text(first.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text((first.isExpense ? "-" : "+") + money(first.amount))
                            .font(.system(size: 16, weight: .semibold)) // 系统原生字体
                            .foregroundColor(first.isExpense ? .red : .green)
                            .lineLimit(1)
                    } else {
                        Text("暂无").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Divider()
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("本月").font(.caption2).foregroundColor(.secondary)
                    Text("支出 \(money(entry.monthExpense))")
                        .font(.caption2).foregroundColor(.red)
                    Text("收入 \(money(entry.monthIncome))")
                        .font(.caption2).foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 今日汇总
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日").font(.caption).foregroundColor(.secondary)
                    addHint
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
                        .font(.system(size: 30, weight: .bold)) // 系统原生字体
                        .foregroundColor(netColor)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
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
                                .font(.footnote) // 项目名缩小，金额字号不变
                                .lineLimit(1)
                            Text(item.timeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 4)
                            Text((item.isExpense ? "-" : "+") + money(item.amount))
                                .font(.system(size: 14, weight: .semibold)) // 系统原生字体，大小不变
                                .foregroundColor(item.isExpense ? .red : .green)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 1) // 压缩行距容纳 13 条
                        if item.id != entry.recentItems.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            // 右下角今日收支：字号与最近记录项一致（footnote）
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text("支 \(money(entry.todayExpense))").foregroundColor(.red)
                    Text("收 \(money(entry.todayIncome))").foregroundColor(.green)
                }
                .font(.footnote)
                .lineLimit(1)
            }
        }
        .padding()
    }

    private func money(_ v: Double) -> String {
        Money.string(v)
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
            RecentItem(id: UUID(), name: "货款", amount: 200, isExpense: false, timeText: "11/17"),
            RecentItem(id: UUID(), name: "宵夜", amount: 32, isExpense: true, timeText: "11/16"),
            RecentItem(id: UUID(), name: "信用卡", amount: 128, isExpense: true, timeText: "11/16"),
            RecentItem(id: UUID(), name: "借呗", amount: 50, isExpense: true, timeText: "11/15"),
            RecentItem(id: UUID(), name: "花呗", amount: 76, isExpense: true, timeText: "11/15")
        ]
        return LedgerEntry(date: now, todayExpense: 88.5, todayIncome: 170,
                           monthExpense: 770.17, monthIncome: 170, recentItems: items)
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
        .description("点击可快速记一笔 · 今日收支、最近记录与本月累计")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LedgerWidget()
    }
}
