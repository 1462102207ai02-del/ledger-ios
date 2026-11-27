import SwiftUI
import Foundation

private enum RecordsFilter: Int {
    case all = 0
    case day = 1
}

private struct RecordGroup: Identifiable {
    var id: String { key }
    let key: String
    let items: [Transaction]
}

struct RecordsView: View {
    @EnvironmentObject var store: DataStore

    @State private var filterMode: RecordsFilter = .all
    @State private var selectedDay = Date()
    @State private var editingRecord: Transaction?

    private var filteredRecords: [Transaction] {
        switch filterMode {
        case .all:
            return store.records
        case .day:
            let cal = Calendar.current
            return store.records.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
        }
    }

    private var sortedRecords: [Transaction] {
        filteredRecords.sorted { $0.date > $1.date }
    }

    private var groupedRecords: [RecordGroup] {
        var order: [String] = []
        var buckets: [String: [Transaction]] = [:]
        for record in sortedRecords {
            let key = dayTitle(record.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(record)
        }
        return order.compactMap { key in
            guard let items = buckets[key] else { return nil }
            return RecordGroup(key: key, items: items)
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 · " + shortDay(date) }
        if cal.isDateInYesterday(date) { return "昨天 · " + shortDay(date) }
        return shortDay(date)
    }

    private func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }

    private var todayRecords: [Transaction] {
        store.records.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayExpense: Double { Money.double(Money.sum(todayRecords, type: .expense)) }
    private var todayIncome: Double { Money.double(Money.sum(todayRecords, type: .income)) }
    private var todayNet: Double { todayIncome - todayExpense }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                todaySummary
                filterBar

                if sortedRecords.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(filterMode == .day ? "这一天没有记录" : "还没有记录").font(.headline)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(groupedRecords) { group in
                            Section(header: Text(group.key)) {
                                ForEach(group.items) { record in
                                    Button {
                                        editingRecord = record
                                    } label: {
                                        RecordRow(record: record)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { indexSet in
                                    for i in indexSet where i < group.items.count {
                                        store.deleteRecord(group.items[i])
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("明细")
            .sheet(item: $editingRecord) { record in
                RecordEditorView(record: record)
            }
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日").font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(todayNet >= 0 ? "总收入" : "总支出")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(Money.string(abs(todayNet)))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(todayNet >= 0 ? .green : .red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出").font(.caption).foregroundColor(.secondary)
                    Text(Money.string(todayExpense))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("收入").font(.caption).foregroundColor(.secondary)
                    Text(Money.string(todayIncome))
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

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("查看范围", selection: $filterMode) {
                Text("全部记录").tag(RecordsFilter.all)
                Text("按日期").tag(RecordsFilter.day)
            }
            .pickerStyle(.segmented)

            if filterMode == .day {
                HStack {
                    DatePicker("选择日期", selection: $selectedDay,
                               displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Spacer()
                    Text("\(filteredRecords.count) 条")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
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
                Text((record.type == .expense ? "-" : "+") + Money.string(record.amount))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(record.type == .expense ? .red : .green)
                    .lineLimit(1)
                Text(formatDate(record.date)).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 编辑记录
struct RecordEditorView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let original: Transaction

    @State private var type: RecordType
    @State private var categoryName: String
    @State private var amountText: String
    @State private var paymentName: String
    @State private var date: Date
    @State private var note: String
    @State private var activePicker: PickerKind?
    @State private var showDeleteConfirm = false

    init(record: Transaction) {
        self.original = record
        _type = State(initialValue: record.type)
        _categoryName = State(initialValue: record.categoryName)
        _amountText = State(initialValue: String(format: "%.2f", record.amount))
        _paymentName = State(initialValue: record.paymentMethodName)
        _date = State(initialValue: record.date)
        _note = State(initialValue: record.note)
    }

    private var availableCategories: [Category] {
        store.categories.filter { $0.type == type }
    }

    private var amount: Double {
        Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSave: Bool {
        amount > 0 && !categoryName.isEmpty && !paymentName.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("类型")) {
                    Picker("类型", selection: $type) {
                        ForEach(RecordType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { newValue in
                        categoryName = store.categories.first { $0.type == newValue }?.name ?? ""
                    }
                }

                Section(header: Text("项目")) {
                    pickerButton(title: categoryName,
                                 count: availableCategories.count,
                                 systemImage: "square.grid.2x2") {
                        activePicker = .category
                    }
                }

                Section(header: Text("金额")) {
                    HStack {
                        Text("¥")
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section(header: Text("支付方式")) {
                    pickerButton(title: paymentName,
                                 count: store.paymentMethods.count,
                                 systemImage: "creditcard") {
                        activePicker = .payment
                    }
                }

                Section(header: Text("日期时间")) {
                    DatePicker("日期时间", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section(header: Text("备注")) {
                    TextField("说点什么…", text: $note)
                }

                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            Text("保存修改").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("删除这笔记录")
                            Spacer()
                        }
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $activePicker) { kind in
                switch kind {
                case .category:
                    TiledPickerSheet(title: "选择项目",
                                     options: availableCategories.map {
                                         PickerOption(name: $0.name, icon: $0.icon)
                                     },
                                     selected: $categoryName)
                case .payment:
                    TiledPickerSheet(title: "选择支付方式",
                                     options: store.paymentMethods.map {
                                         PickerOption(name: $0.name, icon: $0.icon)
                                     },
                                     selected: $paymentName)
                }
            }
            .alert("删除这笔记录？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    store.deleteRecord(original)
                    dismiss()
                }
            } message: {
                Text("删除后无法撤销。")
            }
        }
    }

    private func pickerButton(title: String, count: Int, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                Text(title.isEmpty ? "点按选择" : title)
                    .foregroundColor(title.isEmpty ? .secondary : .primary)
                Spacer()
                Text("\(count) 项").font(.caption).foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .imageScale(.small)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        let updated = Transaction(
            id: original.id,
            type: type,
            categoryName: categoryName,
            amount: amount,
            paymentMethodName: paymentName,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.updateRecord(updated)
        dismiss()
    }
}
