import SwiftUI
import Foundation

// MARK: - 刻度格式化与取整
private func axisMoney(_ value: Double) -> String {
    if value >= 10000 { return String(format: "%.1f万", value / 10000) }
    return String(format: "%.0f", value)
}

/// 把最大值向上取整到「好看」的刻度，避免出现 372.6 这类刻度、柱子也不会顶到天花板。
private func niceCeiling(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let exponent = floor(log10(value))
    let base = pow(10, exponent)
    let fraction = value / base
    let steps: [Double] = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
    let picked = steps.first { $0 >= fraction } ?? 10
    return picked * base
}

private struct MonthPoint {
    let label: String
    let value: Double
}

/// 单行虚线（纯 Path 绘制，不依赖任何 iOS 16 API）。
private struct DashedLine: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

// MARK: - 柱状趋势图（纯 SwiftUI 自绘，兼容 iOS 15）
/// 完整柱状图：Y 轴刻度、虚线网格与基线、日均参考线、圆角柱、
/// 峰值/选中高亮、点按数值气泡、X 轴标签、图例与合计信息。
private struct TrendChart: View {
    let values: [Double]
    let labels: [String]
    let tint: Color
    var height: CGFloat = 168

    @State private var selectedIndex: Int? = nil

    private var ceiling: Double { niceCeiling(values.max() ?? 0) }
    private var total: Double { values.reduce(0, +) }
    private var average: Double { values.isEmpty ? 0 : total / Double(values.count) }
    private var peakIndex: Int? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.firstIndex(of: peak)
    }
    private var activeIndex: Int? { selectedIndex ?? peakIndex }

    private func barHeight(_ value: Double, plotHeight: CGFloat) -> CGFloat {
        guard value > 0 else { return 0 }
        return max(3, CGFloat(value / ceiling) * plotHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("合计").font(.caption).foregroundColor(.secondary)
                Text(Money.string(total))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("日均 \(Money.string(average))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            plot

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 10, height: 10)
                    Text("支出").font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 5) {
                    DashedLine(color: tint.opacity(0.6))
                        .frame(width: 16, height: 1)
                    Text("日均线").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("点按柱子看金额")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var plot: some View {
        VStack(spacing: 5) {
            HStack(alignment: .top, spacing: 4) {
                // Y 轴：上限 / ¾ / ½ / ¼ / 0
                VStack(spacing: 0) {
                    ForEach((0...4).reversed(), id: \.self) { i in
                        Text(axisMoney(ceiling * Double(i) / 4))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxHeight: .infinity, alignment: tickAlignment(i))
                    }
                }
                .frame(width: 38, height: height)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let count = max(values.count, 1)
                    let step = w / CGFloat(count)
                    let barWidth = max(2, min(step * 0.58, 20))

                    ZStack(alignment: .topLeading) {
                        // 网格：4 条虚线 + 1 条实线基线
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { _ in
                                DashedLine(color: Color(.systemGray4).opacity(0.75))
                                    .frame(width: w, height: 1)
                                Spacer(minLength: 0)
                            }
                            Rectangle()
                                .fill(Color(.systemGray3))
                                .frame(width: w, height: 1)
                        }
                        .frame(width: w, height: h)

                        // 平均值参考线
                        if average > 0 {
                            let y = h - CGFloat(average / ceiling) * h
                            DashedLine(color: tint.opacity(0.6))
                                .frame(width: w, height: 1)
                                .position(x: w / 2, y: y)
                        }

                        // 柱体：整列都是点击热区，柱顶圆角
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(values.indices, id: \.self) { i in
                                let barH = barHeight(values[i], plotHeight: h)
                                ZStack(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                selectedIndex = (selectedIndex == i) ? nil : i
                                            }
                                        }
                                    if barH > 0 {
                                        RoundedRectangle(cornerRadius: min(barWidth / 2, 4),
                                                         style: .continuous)
                                            .fill(i == activeIndex ? tint : tint.opacity(0.32))
                                            .frame(width: barWidth, height: barH)
                                    }
                                }
                                .frame(width: step, height: h, alignment: .bottom)
                            }
                        }
                        .frame(width: w, height: h, alignment: .bottom)

                        // 数值气泡：默认落在峰值，点按柱子可切换
                        if let idx = activeIndex, idx < values.count {
                            let barH = barHeight(values[idx], plotHeight: h)
                            let x = step * (CGFloat(idx) + 0.5)
                            let y = max(12, h - barH - 15)
                            HStack(spacing: 5) {
                                if idx < labels.count, !labels[idx].isEmpty {
                                    Text(labels[idx])
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(Money.string(values[idx]))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.systemBackground)))
                            .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                            .fixedSize()
                            .position(x: min(max(x, 48), w - 48), y: y)
                        }

                        // 全零时的空状态，而不是一排空槽
                        if total <= 0 {
                            Text("这段区间还没有支出")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: w, height: h, alignment: .center)
                        }
                    }
                    .frame(width: w, height: h)
                }
                .frame(height: height)
            }

            // X 轴标签：与绘图区左边缘对齐，空字符串占位保持等距
            HStack(spacing: 4) {
                Spacer().frame(width: 38)
                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { i in
                        Text(i < labels.count ? labels[i] : "")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func tickAlignment(_ i: Int) -> Alignment {
        if i == 4 { return .top }
        if i == 0 { return .bottom }
        return .center
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

    /// X 轴只标少量日期，避免 31 个标签挤成一团。
    private var dailyLabels: [String] {
        dailyTrend.indices.map { i in
            let day = i + 1
            let show = day == 1 || day == 10 || day == 20 || i == dailyTrend.count - 1
            return show ? "\(day)" : ""
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("本月每日支出").font(.headline)
                if dailyTrend.isEmpty {
                    Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
                } else {
                    TrendChart(values: dailyTrend, labels: dailyLabels,
                               tint: .red, height: 172)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("近 6 个月支出").font(.headline)
                TrendChart(values: recentMonths.map { $0.value },
                           labels: recentMonths.map { $0.label },
                           tint: .orange, height: 150)
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
                let total = categorySums.reduce(0) { $0 + $1.value }
                ForEach(categorySums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0,
                           share: total > 0 ? item.value / total : 0,
                           color: .red)
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
                let total = paymentSums.reduce(0) { $0 + $1.value }
                ForEach(paymentSums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0,
                           share: total > 0 ? item.value / total : 0,
                           color: .blue)
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
    /// 相对最大项的比例，决定条形长度
    let ratio: Double
    /// 相对合计的真实占比，显示为百分比
    let share: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.subheadline)
                Spacer()
                Text(Money.string(value))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(String(format: "%.0f%%", min(max(share, 0), 1) * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 9)
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: max(0, geo.size.width * CGFloat(min(max(ratio, 0), 1))),
                               height: 9)
                }
            }
            .frame(height: 9)
        }
    }
}
