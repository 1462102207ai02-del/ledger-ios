import SwiftUI
import Foundation

// MARK: - 平铺选择器的通用类型（记一笔页与编辑页共用）
/// 纯文字选项。
struct PickerOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
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

// MARK: - 选择入口按钮（记一笔页与编辑记录页共用）
/// 表单里的一行入口：显示当前选中项与可选项目数，点按弹出居中选择器。
struct PickerEntryButton: View {
    let title: String
    let count: Int
    let systemImage: String
    let action: () -> Void

    var body: some View {
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
}

// MARK: - 半透明居中选择弹窗
/// 自定义 overlay：一层半透明遮罩 + 一张居中卡片。
/// 卡片内是纯文字平铺选项、搜索框，以及一个可现场输入自定义项目的区域。
struct CenteredPickerDialog: View {
    let title: String
    let options: [PickerOption]
    @Binding var selected: String
    let onClose: () -> Void

    @State private var query = ""
    @State private var customName = ""

    private var filtered: [PickerOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 82), spacing: 8)]
    }

    var body: some View {
        ZStack {
            // 半透明遮罩：点空白处即可关闭
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header
                searchField
                Divider()
                optionsGrid
                Divider()
                customSection
            }
            .frame(maxWidth: 420)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.55))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(.systemGray4).opacity(0.7), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(.systemGray5)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .imageScale(.small)
            TextField("搜索项目", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var optionsGrid: some View {
        ScrollView {
            if filtered.isEmpty {
                VStack(spacing: 7) {
                    Text(query.isEmpty ? "还没有可选项目" : "没有匹配的项目")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(query.isEmpty
                         ? "可在下方输入自定义名称，或到「设置」里添加。"
                         : "换个关键词，或在下方直接输入新名称。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filtered) { option in
                        Button {
                            selected = option.name
                            onClose()
                        } label: {
                            Text(option.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected == option.name
                                              ? Color.accentColor.opacity(0.16)
                                              : Color(.systemGray6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selected == option.name ? Color.accentColor : Color.clear,
                                                lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selected == option.name ? .accentColor : .primary)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxHeight: 250)
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义项目")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("输入新名称", text: $customName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    useCustom()
                } label: {
                    Text("选用").fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("保存这笔账单后，新项目会自动留在对应分组里。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    private func useCustom() {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selected = trimmed
        onClose()
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
        availableCategories.map { PickerOption(name: $0.name) }
    }

    private var paymentOptions: [PickerOption] {
        store.paymentMethods.map { PickerOption(name: $0.name) }
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
                        footer: Text(type == .expense ? "点击选择或输入对应的支出项目" : "点击选择或输入对应的收入项目")) {
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
                            .focused($amountFocused)
                    }
                }

                Section(header: Text("支付方式"),
                        footer: Text("点击选择或输入对应的支付方式")) {
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
            .alert(isPresented: $showSaved) {
                Alert(title: Text("已保存"),
                      message: Text(savedMessage),
                      dismissButton: .default(Text("好")))
            }
        }
        .overlay(pickerOverlay)
    }

    /// 半透明居中选择弹窗，挂在页面层，不受键盘收起手势干扰。
    private var pickerOverlay: some View {
        ZStack {
            if let kind = activePicker {
                switch kind {
                case .category:
                    CenteredPickerDialog(
                        title: type == .expense ? "选择支出项目" : "选择收入项目",
                        options: categoryOptions,
                        selected: $categoryName,
                        onClose: { activePicker = nil }
                    )
                case .payment:
                    CenteredPickerDialog(
                        title: "选择支付方式",
                        options: paymentOptions,
                        selected: $paymentName,
                        onClose: { activePicker = nil }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activePicker != nil)
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
        // 弹窗里现场输入的自定义项目，随这笔账单一起落库到对应分组；
        // 取消记账不会留下孤立项目，已存在的同名项目也会自动跳过。
        store.absorbCustomSelections(categoryName: categoryName, type: type,
                                     paymentName: paymentName)
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
