import SwiftUI
import Foundation

struct StatisticsView: View {
    @EnvironmentObject var store: DataStore

    private func isThisMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    private var monthRecords: [Transaction] {
        store.records.filter { isThisMonth($0.date) }
    }

    private var monthExpense: Double {
        monthRecords.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var monthIncome: Double {
        monthRecords.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    private var categorySums: [(name: String, value: Double)] {
        var dict: [String: Double] = [:]
        for r in monthRecords where r.type == .expense {
            dict[r.categoryName, default: 0] += r.amount
        }
        return dict.map { (name: $0.key, value: $0.value) }
                   .sorted { $0.value > $1.value }
    }

    private var paymentSums: [(name: String, value: Double)] {
        var dict: [String: Double] = [:]
        for r in monthRecords where r.type == .expense {
            dict[r.paymentMethodName, default: 0] += r.amount
        }
        return dict.map { (name: $0.key, value: $0.value) }
                   .sorted { $0.value > $1.value }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard
                    categorySection
                    paymentSection
                }
                .padding()
            }
            .navigationTitle("统计")
        }
    }

    private var summaryCard: some View {
        HStack {
            StatColumn(title: "本月支出", value: monthExpense, color: .red)
            Divider().frame(height: 36)
            StatColumn(title: "本月收入", value: monthIncome, color: .green)
            Divider().frame(height: 36)
            StatColumn(title: "结余", value: monthIncome - monthExpense, color: .blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
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
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(String(format: "¥%.0f", value))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
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
                Text(String(format: "¥%.2f", value)).font(.subheadline).foregroundColor(.secondary)
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
