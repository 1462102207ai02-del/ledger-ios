import SwiftUI
import Foundation

// MARK: - 平铺选择器的通用类型（记一笔页与编辑页共用）
/// 纯文字选项。
/// id 用项目名而不是每次新建的 UUID：选项数组是计算属性，父视图每次刷新都会重新生成，
/// 若 id 每次都变，LazyVGrid 的所有 cell 身份会全部失效并被重建，选中态与点击容易错乱。
struct PickerOption: Identifiable, Hashable {
    var id: String { name }
    let name: String
}

extension PickerOption {
    /// 现场输入的自定义名称还没落库时也放进选项首位，
    /// 避免再次打开弹窗时看不到当前选中态（记一笔页与编辑页共用）。
    static func list(from names: [String], current: String) -> [PickerOption] {
        var options = names.map { PickerOption(name: $0) }
        if !current.isEmpty && !options.contains(where: { $0.name == current }) {
            options.insert(PickerOption(name: current), at: 0)
        }
        return options
    }
}

enum PickerKind: Identifiable {
    case category
    /// 渠道选择器：标题、图标与选项由当前收支类型决定，不再写死成「支付方式」。
    case method

    var id: String {
        switch self {
        case .category: return "category"
        case .method: return "method"
        }
    }
}

// MARK: - 紧凑表单行
/// 记一笔页的 Form 行统一收紧上下内边距，让整张表单（含底部的保存按钮）
/// 能落在底栏之上完整显示，不必滚动到底才看得见「保存」。
private extension View {
    func compactRow() -> some View {
        listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
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
            .padding(.vertical, 8)
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
                    ForEach(filtered, id: \.name) { option in
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

    /// 表单草稿用 SceneStorage 而不是普通 @State。
    /// iOS 15 下键盘弹出 / TabView 重排会重建视图层级，@State 可能被重置成初始值，
    /// 于是刚选好的支出项目会被 setupDefaults() 重新填成列表第一项 —— 就是「自己跳到别的项」。
    /// SceneStorage 由系统在场景级保存，视图重建后自动恢复，不随 @State 一起被重置。
    @SceneStorage("ledger.add.type") private var typeRaw: String = RecordType.expense.rawValue
    @SceneStorage("ledger.add.category") private var categoryName: String = ""
    /// 支出与收入各记一个渠道草稿：切到「收入」不会把刚选好的支付方式顶掉，切回来也还在。
    @SceneStorage("ledger.add.payment") private var paymentName: String = ""
    @SceneStorage("ledger.add.receipt") private var receiptName: String = ""

    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showSaved = false
    @State private var savedMessage = ""
    @State private var activePicker: PickerKind?

    @FocusState private var amountFocused: Bool

    private var type: RecordType { RecordType(rawValue: typeRaw) ?? .expense }

    /// 只在真正切换收支类型时才把项目换成新类型的第一项；
    /// 相同值直接忽略，避免 Picker 在视图重建时重新绑定 selection 造成误触发。
    /// 渠道草稿不做重置：两种类型各自记着自己的选择。
    private var typeBinding: Binding<RecordType> {
        Binding(
            get: { RecordType(rawValue: typeRaw) ?? .expense },
            set: { newType in
                guard newType != type else { return }
                typeRaw = newType.rawValue
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

    // MARK: 渠道（支付方式 / 收款方式）
    private var methodTitle: String { type.methodGroup.title }

    private var methodName: String { type == .expense ? paymentName : receiptName }

    /// 选择弹窗统一绑到当前类型的那一份草稿，避免两个 SceneStorage 互相覆盖。
    private var methodBinding: Binding<String> {
        Binding(
            get: { type == .expense ? paymentName : receiptName },
            set: { newValue in
                if type == .expense { paymentName = newValue } else { receiptName = newValue }
            }
        )
    }

    private var availableMethods: [PaymentMethod] {
        store.methodList(type.methodGroup)
    }

    private var categoryOptions: [PickerOption] {
        PickerOption.list(from: availableCategories.map { $0.name }, current: categoryName)
    }

    private var methodOptions: [PickerOption] {
        PickerOption.list(from: availableMethods.map { $0.name }, current: methodName)
    }

    private var canSave: Bool {
        amount > 0 && !categoryName.isEmpty && !methodName.isEmpty
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
                    .compactRow()
                }

                Section(header: Text(type == .expense ? "支出项目" : "收入项目")) {
                    PickerEntryButton(title: categoryName,
                                      count: availableCategories.count,
                                      systemImage: "square.grid.2x2") {
                        activePicker = .category
                    }
                    .compactRow()
                }

                Section(header: Text("金额")) {
                    HStack {
                        Text("¥")
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                    }
                    .compactRow()
                }

                Section(header: Text(methodTitle)) {
                    PickerEntryButton(title: methodName,
                                      count: availableMethods.count,
                                      systemImage: type.methodGroup.systemImage) {
                        activePicker = .method
                    }
                    .compactRow()
                }

                Section(header: Text("日期时间")) {
                    DatePicker("日期时间", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .compactRow()
                }

                Section(header: Text("备注")) {
                    TextField("说点什么…", text: $note)
                        .compactRow()
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
                    .compactRow()
                }
            }
            // 行最小高度 44 → 36，配合上面的紧凑内边距把整张表单压进一屏，
            // 保存按钮不再被推到底栏之下。iOS 15 无 listSectionSpacing，用这个环境值最稳。
            .environment(\.defaultMinListRowHeight, 36)
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
                case .method:
                    CenteredPickerDialog(
                        title: "选择\(methodTitle)",
                        options: methodOptions,
                        selected: methodBinding,
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
            paymentName = store.methodList(.payment).first?.name ?? ""
        }
        if receiptName.isEmpty {
            receiptName = store.methodList(.receipt).first?.name ?? ""
        }
    }

    private func save() {
        guard canSave else { return }
        // 弹窗里现场输入的自定义项目，随这笔账单一起落库到对应分组；
        // 取消记账不会留下孤立项目，已存在的同名项目也会自动跳过。
        store.absorbCustomSelections(categoryName: categoryName, type: type,
                                     methodName: methodName)
        let record = Transaction(
            type: type,
            categoryName: categoryName,
            amount: amount,
            paymentMethodName: methodName,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addRecord(record)
        savedMessage = "\(type.rawValue) \(Money.string(amount)) 已记入「\(categoryName)」"
        showSaved = true
        amountText = ""
        note = ""
        date = Date()
        // 连续记账：项目和当前类型的渠道选择保留，键盘直接回到金额
        amountFocused = true
    }
}
