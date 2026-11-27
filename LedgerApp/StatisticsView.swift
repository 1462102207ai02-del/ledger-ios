import SwiftUI
import Foundation

private struct MonthPoint {
    let label: String
    let value: Double
}

/// 纯 SwiftUI 自绘柱状趋势图：不依赖 iOS 16 才有的 Charts 框架。
private struct TrendChart: View {
    let values: [Double]
    let labels: [String]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let barArea = max(geo.size.height - 18, 10)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.indices), id: \.self) { i in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(i == values.count - 1
                                  ? Color.accentColor
                                  : Color.accentColor.opacity(0.4))
                            .frame(height: max(2, CGFloat(values[i] / maxValue) * barArea))
                        Text(i < labels.count ? labels[i] : "")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: height)
    }
}

struct StatisticsView: View {
    @EnvironmentObject var store: DataStore

    @State private var anchorMonth = Date()

    private var cal: Calendar { Calendar.current }

    private func isInSelectedMonth(_ date: Date) -> Bool {
        cal.isDate(date, equalTo: anchorMonth, toGranularity: .month)
    }

    private var monthRecords: [Transaction] {
        store.records.filter { isInSelectedMonth($0.date) }
    }

    private var monthExpense: Decimal { Money.sum(monthRecords, type: .expense) }
    private var monthIncome: Decimal { Money.sum(monthRecords, type: .income) }
    private var monthBalance: Decimal { monthIncome - monthExpense }

    private var categorySums: [(name: String, value: Double)] {
        var dict: [String: Decimal] = [:]
        for r in monthRecords where r.type == .expense {
            dict[r.categoryName, default: Decimal(0)] += Money.decimal(r.amount)
        }
        return dict.map { (name: $0.key, value: Money.double($0.value)) }
                   .sorted { $0.value > $1.value }
    }

    private var paymentSums: [(name: String, value: Double)] {
        var dict: [String: Decimal] = [:]
        for r in monthRecords where r.type == .expense {
            dict[r.paymentMethodName, default: Decimal(0)] += Money.decimal(r.amount)
        }
        return dict.map { (name: $0.key, value: Money.double($0.value)) }
                   .sorted { $0.value > $1.value }
    }

    /// 选中月份内每一天的支出，用于日趋势。
    private var dailyTrend: [Double] {
        guard let range = cal.range(of: .day, in: .month, for: anchorMonth),
              let start = cal.date(from: cal.dateComponents([.year, .month], from: anchorMonth)) else {
            return []
        }
        return range.compactMap { dayNumber -> Double in
            guard let day = cal.date(byAdding: .day, value: dayNumber - 1, to: start) else { return 0 }
            let items = monthRecords.filter {
                cal.isDate($0.date, inSameDayAs: day) && $0.type == .expense
            }
            return Money.double(Money.sum(items, type: .expense))
        }
    }

    private var dailyLabels: [String] {
        dailyTrend.indices.map { i in
            let day = i + 1
            return (day == 1 || day % 5 == 0 || i == dailyTrend.count - 1) ? "\(day)" : ""
        }
    }

    /// 近 6 个月支出，用于月趋势。
    private var recentMonths: [MonthPoint] {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: anchorMonth)) else {
            return []
        }
        return (0..<6).reversed().compactMap { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: start) else { return nil }
            let items = store.records.filter {
                cal.isDate($0.date, equalTo: m, toGranularity: .month) && $0.type == .expense
            }
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月"
            return MonthPoint(label: f.string(from: m),
                              value: Money.double(Money.sum(items, type: .expense)))
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthSwitcher
                    summaryCard
                    trendSection
                    categorySection
                    paymentSection
                }
                .padding()
            }
            .navigationTitle("统计")
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(isCurrentMonth)
        }
    }

    private var isCurrentMonth: Bool {
        cal.isDate(anchorMonth, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: anchorMonth) {
            anchorMonth = d
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: anchorMonth)
    }

    private var summaryCard: some View {
        HStack {
            StatColumn(title: "支出", value: Money.string(monthExpense), color: .red)
            Divider().frame(height: 36)
            StatColumn(title: "收入", value: Money.string(monthIncome), color: .green)
            Divider().frame(height: 36)
            StatColumn(title: "结余",
                       value: Money.string(monthBalance),
                       color: Money.double(monthBalance) < 0 ? .red : .green)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("本月每日支出").font(.headline)
                if dailyTrend.isEmpty {
                    Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
                } else {
                    TrendChart(values: dailyTrend, labels: dailyLabels, height: 110)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("近 6 个月支出").font(.headline)
                TrendChart(values: recentMonths.map { $0.value },
                           labels: recentMonths.map { $0.label },
                           height: 100)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月支出 · 按项目").font(.headline)
            if categorySums.isEmpty {
                Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
            } else {
                let maxValue = categorySums.first?.value ?? 1
                ForEach(categorySums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0, color: .red)
                }
            }
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月支出 · 按支付方式").font(.headline)
            if paymentSums.isEmpty {
                Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
            } else {
                let maxValue = paymentSums.first?.value ?? 1
                ForEach(paymentSums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0, color: .blue)
                }
            }
        }
    }
}

private struct StatColumn: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BarRow: View {
    let title: String
    let value: Double
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(Money.string(value)).font(.subheadline).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.systemGray5)).frame(height: 10).cornerRadius(5)
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)), height: 10)
                        .cornerRadius(5)
                }
            }
            .frame(height: 10)
        }
    }
}
