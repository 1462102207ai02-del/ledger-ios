import SwiftUI
import Foundation

/// 明细页查看范围。保留 Int rawValue 供 SceneStorage 持久化：
/// iOS 15 下 TabView 切换 / 键盘弹出会重建视图层级，普通 @State 会被重置，
/// 用户选好的「按日期 + 某一天」不该因为切个页面就丢。与记一笔页的草稿策略一致。
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

    /// 筛选范围与所选日期用 SceneStorage 持久化，避免 iOS 15 视图重建时被重置回默认。
    /// Date 不能直接存 SceneStorage，改存时间戳；0 表示「尚未选择，默认今天」。
    @SceneStorage("ledger.records.filter") private var filterRaw: Int = RecordsFilter.all.rawValue
    @SceneStorage("ledger.records.dayStamp") private var selectedDayStamp: Double = 0
    @State private var editingRecord: Transaction?

    private var filterMode: RecordsFilter {
        RecordsFilter(rawValue: filterRaw) ?? .all
    }

    private var filterBinding: Binding<RecordsFilter> {
        Binding(get: { RecordsFilter(rawValue: filterRaw) ?? .all },
                set: { filterRaw = $0.rawValue })
    }

    private var selectedDay: Date {
        selectedDayStamp == 0 ? Date() : Date(timeIntervalSinceReferenceDate: selectedDayStamp)
    }

    private var selectedDayBinding: Binding<Date> {
        Binding(
            get: { selectedDayStamp == 0 ? Date() : Date(timeIntervalSinceReferenceDate: selectedDayStamp) },
            set: { selectedDayStamp = $0.timeIntervalSinceReferenceDate }
        )
    }

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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 · " + shortDay(date) }
        if cal.isDateInYesterday(date) { return "昨天 · " + shortDay(date) }
        return shortDay(date)
    }

    private func shortDay(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    // MARK: - 汇总（跟随筛选范围）

    /// 全部记录模式显示「今日」速览；按日期模式显示所选那一整天。
    /// 标题始终准确标注数据来源，不再出现「写着今日、明细却是别的日期」的误导。
    private var summaryRecords: [Transaction] {
        switch filterMode {
        case .all:
            return store.records.filter { Calendar.current.isDateInToday($0.date) }
        case .day:
            return filteredRecords
        }
    }

    private var summaryTitle: String {
        switch filterMode {
        case .all: return "今日"
        case .day:
            let cal = Calendar.current
            if cal.isDateInToday(selectedDay) { return "今天" }
            if cal.isDateInYesterday(selectedDay) { return "昨天" }
            return shortDay(selectedDay)
        }
    }

    private var summaryExpense: Decimal { Money.sum(summaryRecords, type: .expense) }
    private var summaryIncome: Decimal { Money.sum(summaryRecords, type: .income) }
    private var summaryBalance: Decimal { summaryIncome - summaryExpense }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar
                if !sortedRecords.isEmpty { summaryCard }

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

    /// 紧凑的三列小计：支出 / 收入 / 结余，与统计页共用同一套视觉语言。
    /// 位置放在筛选栏下方、明细列表上方，形成「选范围 → 看小计 → 看流水」的从属关系；
    /// 始终可见、不随列表滚走，也不挤占明细行。
    /// 数值一律走 Decimal 求和，结余是真实的「收入 − 支出」，不再拿净额冒充「总收入/总支出」。
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(summaryTitle).font(.headline)
                Spacer()
                Text("\(summaryRecords.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                StatColumn(title: "支出", value: Money.string(summaryExpense), color: .red)
                Divider().frame(height: 30)
                StatColumn(title: "收入", value: Money.string(summaryIncome), color: .green)
                Divider().frame(height: 30)
                StatColumn(title: "结余", value: Money.string(summaryBalance),
                           color: Money.double(summaryBalance) < 0 ? .red : .green)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("查看范围", selection: filterBinding) {
                Text("全部记录").tag(RecordsFilter.all)
                Text("按日期").tag(RecordsFilter.day)
            }
            .pickerStyle(.segmented)

            if filterMode == .day {
                DatePicker("选择日期", selection: selectedDayBinding,
                           displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private func formatDate(_ d: Date) -> String {
        Self.timeFormatter.string(from: d)
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

    /// 与记一笔页一致：用 Binding setter 处理收支类型切换，相同值直接忽略，
    /// 避免 .onChange(of:) 在视图重建 / Picker 重新绑定时误把项目重置成第一项。
    private var typeBinding: Binding<RecordType> {
        Binding(
            get: { type },
            set: { newType in
                guard newType != type else { return }
                type = newType
                categoryName = store.categories.first { $0.type == newType }?.name ?? ""
            }
        )
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
                    Picker("类型", selection: typeBinding) {
                        ForEach(RecordType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("项目"),
                        footer: Text("点击选择或输入对应的项目")) {
                    PickerEntryButton(title: categoryName,
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
                    PickerEntryButton(title: paymentName,
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
        .overlay(pickerOverlay)
    }

    /// 半透明居中选择弹窗：与记一笔页共用同一个组件。
    private var pickerOverlay: some View {
        ZStack {
            if let kind = activePicker {
                switch kind {
                case .category:
                    CenteredPickerDialog(
                        title: "选择项目",
                        options: availableCategories.map { PickerOption(name: $0.name) },
                        selected: $categoryName,
                        onClose: { activePicker = nil }
                    )
                case .payment:
                    CenteredPickerDialog(
                        title: "选择支付方式",
                        options: store.paymentMethods.map { PickerOption(name: $0.name) },
                        selected: $paymentName,
                        onClose: { activePicker = nil }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activePicker != nil)
    }

    private func save() {
        guard canSave else { return }
        // 现场输入的自定义项目，随这次修改一起落库到对应分组
        store.absorbCustomSelections(categoryName: categoryName, type: type,
                                     paymentName: paymentName)
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
