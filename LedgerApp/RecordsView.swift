import SwiftUI
import Foundation

struct RecordsView: View {
    @EnvironmentObject var store: DataStore

    private var sortedRecords: [Transaction] {
        store.records.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            Group {
                if sortedRecords.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("还没有记录").font(.headline)
                        Text("去「记一笔」开始吧").font(.subheadline).foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(sortedRecords) { record in
                            RecordRow(record: record, icon: iconName(for: record))
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

    private func iconName(for record: Transaction) -> String {
        store.categories.first { $0.name == record.categoryName }?.icon ?? "🧾"
    }
}

private struct RecordRow: View {
    let record: Transaction
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(record.type == .expense ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                Text(icon).font(.system(size: 18))
            }
            .frame(width: 40, height: 40)

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
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}
