import SwiftUI
import Foundation

// MARK: - 平铺选择器的通用类型（记一笔页与编辑页共用）
struct PickerOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
}

enum PickerKind: Identifiable {
    case category
    case payment

    var id: String {
        switch self {
        case .category: return "category"
        case .payment: return "payment"
        }
    }
}

/// 点按后弹出的平铺网格选择器：项目再多也不会拉出一条长列表，并支持搜索。
struct TiledPickerSheet: View {
    let title: String
    let options: [PickerOption]
    @Binding var selected: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 88), spacing: 10)]
    }

    var body: some View {
        NavigationView {
            Group {
                if options.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("还没有可选项目").font(.headline)
                        Text("请到「设置」中添加。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(filtered) { option in
                                Button {
                                    selected = option.name
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(option.icon).font(.system(size: 26))
                                        Text(option.name)
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selected == option.name
                                                  ? Color.accentColor.opacity(0.14)
                                                  : Color(.systemGray6))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(selected == option.name ? Color.accentColor : Color.clear,
                                                    lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.primary)
                            }
                        }
                        .padding()
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索项目")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 记一笔
struct AddRecordView: View {
    @EnvironmentObject var store: DataStore

    /// 由 ContentView 传入：小组件跳转时递增，用于自动聚焦金额。
    let focusToken: Int

    @State private var type: RecordType = .expense
    @State private var categoryName = ""
    @State private var amountText = ""
    @State private var paymentName = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showSaved = false
    @State private var savedMessage = ""
    @State private var activePicker: PickerKind?

    @FocusState private var amountFocused: Bool

    private var availableCategories: [Category] {
        store.categories.filter { $0.type == type }
    }

    private var amount: Double {
        Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSave: Bool {
        amount > 0 && !categoryName.isEmpty && !paymentName.isEmpty
    }

    private var categoryOptions: [PickerOption] {
        availableCategories.map { PickerOption(name: $0.name, icon: $0.icon) }
    }

    private var paymentOptions: [PickerOption] {
        store.paymentMethods.map { PickerOption(name: $0.name, icon: $0.icon) }
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

                Section(header: Text(type == .expense ? "支出项目" : "收入项目"),
                        footer: Text("点按后平铺展示全部项目，可搜索；项目在「设置」里管理。")) {
                    tiledSelectionButton(title: categoryName,
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
                            .focused($amountFocused)
                    }
                }

                Section(header: Text("支付方式")) {
                    tiledSelectionButton(title: paymentName,
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
                            Text("保存").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("记一笔")
            .onAppear {
                setupDefaults()
                if focusToken > 0 { amountFocused = true }
            }
            .onChange(of: focusToken) { _ in amountFocused = true }
            .sheet(item: $activePicker) { kind in
                switch kind {
                case .category:
                    TiledPickerSheet(title: type == .expense ? "选择支出项目" : "选择收入项目",
                                     options: categoryOptions,
                                     selected: $categoryName)
                case .payment:
                    TiledPickerSheet(title: "选择支付方式",
                                     options: paymentOptions,
                                     selected: $paymentName)
                }
            }
            .alert(isPresented: $showSaved) {
                Alert(title: Text("已保存"),
                      message: Text(savedMessage),
                      dismissButton: .default(Text("好")))
            }
        }
    }

    /// 入口按钮：显示当前选中项与项目总数，点按弹出平铺选择器。
    private func tiledSelectionButton(title: String, count: Int, systemImage: String,
                                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                Text(title.isEmpty ? "点按选择" : title)
                    .foregroundColor(title.isEmpty ? .secondary : .primary)
                Spacer()
                Text("\(count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

    private func setupDefaults() {
        if categoryName.isEmpty {
            categoryName = availableCategories.first?.name ?? ""
        }
        if paymentName.isEmpty {
            paymentName = store.paymentMethods.first?.name ?? ""
        }
    }

    private func save() {
        guard canSave else { return }
        let record = Transaction(
            type: type,
            categoryName: categoryName,
            amount: amount,
            paymentMethodName: paymentName,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addRecord(record)
        savedMessage = "\(type.rawValue) \(Money.string(amount)) 已记入「\(categoryName)」"
        showSaved = true
        amountText = ""
        note = ""
        date = Date()
        // 连续记账：项目和支付方式保留，键盘直接回到金额
        amountFocused = true
    }
}
