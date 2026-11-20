import SwiftUI
import Foundation

struct RecordsView: View {
    @EnvironmentObject var store: DataStore

    private var sortedRecords: [Transaction] {
        store.records.sorted { $0.date > $1.date }
    }

    private var todayRecords: [Transaction] {
        store.records.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayExpense: Double {
        todayRecords.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var todayIncome: Double {
        todayRecords.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    /// 当天净额：收入 − 支出。为正显示总收入，为负显示总支出。
    private var todayNet: Double {
        todayIncome - todayExpense
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                todaySummary

                if sortedRecords.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("还没有记录").font(.headline)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(sortedRecords) { record in
                            RecordRow(record: record)
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                store.deleteRecord(sortedRecords[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("明细")
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日").font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(todayNet >= 0 ? "总收入" : "总支出")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(String(format: "¥%.2f", abs(todayNet)))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(todayNet >= 0 ? .green : .red)
            }

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出").font(.caption).foregroundColor(.secondary)
                    Text(String(format: "¥%.2f", todayExpense))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("收入").font(.caption).foregroundColor(.secondary)
                    Text(String(format: "¥%.2f", todayIncome))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct RecordRow: View {
    let record: Transaction

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.categoryName).font(.system(size: 15, weight: .medium))
                HStack(spacing: 6) {
                    Text(record.paymentMethodName)
                    if !record.note.isEmpty {
                        Text("·")
                        Text(record.note).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%@¥%.2f", record.type == .expense ? "-" : "+", record.amount))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(record.type == .expense ? .red : .green)
                Text(formatDate(record.date)).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
