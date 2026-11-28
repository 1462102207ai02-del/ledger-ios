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
/// legend / emptyText 由调用方按收支方向传入，图里不再写死「支出」。
private struct TrendChart: View {
    let values: [Double]
    let labels: [String]
    let tint: Color
    let legend: String
    let emptyText: String
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
                    Text(legend).font(.caption2).foregroundColor(.secondary)
                }
                HStack(spacing: 5) {
                    DashedLine(color: tint.opacity(0.6))
                        .frame(width: 16, height: 1)
                    Text("日均线").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("点击查看具体金额")
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
                            Text(emptyText)
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

// MARK: - 按方向参数化的月度统计数据源
/// 首页卡片与详情页共用同一份计算，支出/收入只是传入不同的 type。
/// 汇总一律走 Decimal，避免大量小额累加后的浮点误差。
private struct MonthStats {
    let type: RecordType
    let total: Decimal
    let count: Int
    let dayCount: Int
    let previousTotal: Decimal
    let categorySums: [(name: String, value: Double)]
    let methodSums: [(name: String, value: Double)]
    let dailyTrend: [Double]
    let dailyLabels: [String]
    let recentMonths: [MonthPoint]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f
    }()

    var dailyAverage: Decimal {
        guard dayCount > 0 else { return 0 }
        return total / Decimal(dayCount)
    }

    /// 上月同方向总额为 0 时不显示环比，避免出现除零或「∞%」。
    var changeRatio: Double? {
        guard previousTotal > 0 else { return nil }
        return Money.double((total - previousTotal) / previousTotal)
    }

    private static func sums(_ items: [Transaction], by key: (Transaction) -> String)
        -> [(name: String, value: Double)] {
        var dict: [String: Decimal] = [:]
        for r in items {
            dict[key(r), default: Decimal(0)] += Money.decimal(r.amount)
        }
        return dict.map { (name: $0.key, value: Money.double($0.value)) }
                   .sorted { $0.value > $1.value }
    }

    static func make(records: [Transaction], month: Date, type: RecordType,
                     cal: Calendar = .current) -> MonthStats {
        let items = records.filter {
            cal.isDate($0.date, equalTo: month, toGranularity: .month) && $0.type == type
        }
        let total = Money.sum(items.map { $0.amount })

        // 当月每日趋势与 X 轴标签：只标 1 / 10 / 20 / 月末，避免 31 个标签挤成一团
        var daily: [Double] = []
        var labels: [String] = []
        var dayCount = 0
        if let range = cal.range(of: .day, in: .month, for: month),
           let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) {
            dayCount = range.count
            for dayNumber in range {
                let day = cal.date(byAdding: .day, value: dayNumber - 1, to: start) ?? start
                let dayItems = items.filter { cal.isDate($0.date, inSameDayAs: day) }
                daily.append(Money.double(Money.sum(dayItems.map { $0.amount })))
                let show = dayNumber == 1 || dayNumber == 10 || dayNumber == 20 || dayNumber == range.count
                labels.append(show ? "\(dayNumber)" : "")
            }
        }

        // 近 6 个月同方向合计
        var recent: [MonthPoint] = []
        var previous: Decimal = 0
        if let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) {
            for offset in (0..<6).reversed() {
                guard let m = cal.date(byAdding: .month, value: -offset, to: start) else { continue }
                let mItems = records.filter {
                    cal.isDate($0.date, equalTo: m, toGranularity: .month) && $0.type == type
                }
                recent.append(MonthPoint(label: monthFormatter.string(from: m),
                                         value: Money.double(Money.sum(mItems.map { $0.amount }))))
            }
            if let p = cal.date(byAdding: .month, value: -1, to: start) {
                let pItems = records.filter {
                    cal.isDate($0.date, equalTo: p, toGranularity: .month) && $0.type == type
                }
                previous = Money.sum(pItems.map { $0.amount })
            }
        }

        return MonthStats(
            type: type,
            total: total,
            count: items.count,
            dayCount: dayCount,
            previousTotal: previous,
            categorySums: sums(items, by: { $0.categoryName }),
            methodSums: sums(items, by: { $0.paymentMethodName }),
            dailyTrend: daily,
            dailyLabels: labels,
            recentMonths: recent
        )
    }
}

// MARK: - 月份切换器（统计首页与详情页共用同一个绑定，切月状态同步）
private struct MonthSwitcher: View {
    @Binding var month: Date

    private var cal: Calendar { Calendar.current }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    private var isCurrentMonth: Bool {
        cal.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private func shift(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    var body: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()
            Text(Self.titleFormatter.string(from: month)).font(.headline)
            Spacer()

            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(isCurrentMonth)
        }
    }
}

// MARK: - 统计首页：支出 / 收入两组，各一张卡片
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

    private var balance: Decimal {
        Money.sum(monthRecords, type: .income) - Money.sum(monthRecords, type: .expense)
    }

    private func stats(for type: RecordType) -> MonthStats {
        MonthStats.make(records: store.records, month: anchorMonth, type: type)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MonthSwitcher(month: $anchorMonth)
                    balanceBanner
                    ForEach(RecordType.allCases) { type in
                        NavigationLink(
                            destination: StatisticsDetailView(type: type, month: $anchorMonth)
                        ) {
                            StatGroupCard(stats: stats(for: type))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("统计")
        }
    }

    /// 结余不单独占一张卡：保留为一行小字，避免与两组主卡竞争视觉。
    private var balanceBanner: some View {
        HStack {
            Text("本月结余").font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(Money.string(balance))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Money.double(balance) < 0 ? .red : .green)
        }
        .padding(.horizontal, 4)
    }
}

/// 分组卡片：只外显主要数据，点按进入该方向的完整统计详情。
private struct StatGroupCard: View {
    let stats: MonthStats

    private var tint: Color { stats.type == .expense ? .red : .green }
    private var icon: String {
        stats.type == .expense ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                    .imageScale(.medium)
                Text(stats.type.rawValue).font(.headline)
                Spacer(minLength: 6)
                if let ratio = stats.changeRatio {
                    Text(String(format: "较上月 %+.1f%%", ratio * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("上月无记录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .imageScale(.small)
            }

            Text(Money.string(stats.total))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 6) {
                Text("\(stats.count) 笔")
                Text("·")
                Text("日均 \(Money.string(stats.dailyAverage))")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let top = stats.categorySums.first {
                HStack(spacing: 5) {
                    Text("最大项").font(.caption).foregroundColor(.secondary)
                    Text(top.name).font(.caption).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Money.string(top.value))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("本月暂无\(stats.type.rawValue)记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - 统计详情：同一套图表，按方向过滤
private struct StatisticsDetailView: View {
    @EnvironmentObject var store: DataStore
    let type: RecordType
    /// 与首页共享同一个月份：在详情里切月，返回后首页也是同一月。
    @Binding var month: Date

    private var stats: MonthStats {
        MonthStats.make(records: store.records, month: month, type: type)
    }

    private var tint: Color { type == .expense ? .red : .green }
    private var accent: Color { type == .expense ? .orange : .mint }
    private var methodTitle: String { type.methodGroup.title }
    private var categoryTitle: String { type == .expense ? "支出项目" : "收入项目" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MonthSwitcher(month: $month)
                overview
                trendSection
                categorySection
                methodSection
            }
            .padding()
        }
        .navigationTitle("\(type.rawValue)统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overview: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(type.rawValue)合计").font(.caption).foregroundColor(.secondary)
                Text(Money.string(stats.total))
                    .font(.title2.weight(.bold))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(stats.count) 笔").font(.subheadline)
                Text("日均 \(Money.string(stats.dailyAverage))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("每日\(type.rawValue)").font(.headline)
                if stats.dailyTrend.isEmpty {
                    Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
                } else {
                    TrendChart(values: stats.dailyTrend, labels: stats.dailyLabels,
                               tint: tint, legend: type.rawValue,
                               emptyText: "这段区间还没有\(type.rawValue)", height: 172)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("近 6 个月\(type.rawValue)").font(.headline)
                TrendChart(values: stats.recentMonths.map { $0.value },
                           labels: stats.recentMonths.map { $0.label },
                           tint: accent, legend: type.rawValue,
                           emptyText: "近 6 个月没有\(type.rawValue)记录", height: 150)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按\(categoryTitle)").font(.headline)
            if stats.categorySums.isEmpty {
                Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
            } else {
                let maxValue = stats.categorySums.first?.value ?? 1
                let total = stats.categorySums.reduce(0) { $0 + $1.value }
                ForEach(stats.categorySums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0,
                           share: total > 0 ? item.value / total : 0,
                           color: tint)
                }
            }
        }
    }

    /// 支出按「支付方式」、收入按「收款方式」，与记一笔页的分组口径一致。
    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按\(methodTitle)").font(.headline)
            if stats.methodSums.isEmpty {
                Text("暂无数据").foregroundColor(.secondary).font(.subheadline)
            } else {
                let maxValue = stats.methodSums.first?.value ?? 1
                let total = stats.methodSums.reduce(0) { $0 + $1.value }
                ForEach(stats.methodSums, id: \.name) { item in
                    BarRow(title: item.name, value: item.value,
                           ratio: maxValue > 0 ? item.value / maxValue : 0,
                           share: total > 0 ? item.value / total : 0,
                           color: accent)
                }
            }
        }
    }
}

/// 统计页与明细页共用的三列小计单元（同 target 内复用，避免两处各写一份）。
struct StatColumn: View {
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
