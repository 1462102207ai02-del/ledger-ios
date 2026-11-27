import SwiftUI

private enum DataSheet: Identifiable {
    case share(URL)
    case importer

    var id: String {
        switch self {
        case .share(let url): return "share-\(url.lastPathComponent)"
        case .importer: return "importer"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: DataStore

    @State private var newExpense = ""
    @State private var newIncome = ""
    @State private var newPayment = ""
    @State private var showResetConfirm = false

    // 三个大类默认收起：进设置页先看到分组，点开才铺开项目清单
    @State private var expenseExpanded = false
    @State private var incomeExpanded = false
    @State private var paymentExpanded = false

    // 重命名弹窗状态
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var showRenameError = false

    // 数据导入导出
    @State private var activeDataSheet: DataSheet?
    @State private var importMessage: String?

    private enum RenameTarget: Identifiable {
        case category(Category)
        case payment(PaymentMethod)

        var id: String {
            switch self {
            case .category(let c): return "c-\(c.id.uuidString)"
            case .payment(let m): return "p-\(m.id.uuidString)"
            }
        }

        var currentName: String {
            switch self {
            case .category(let c): return c.name
            case .payment(let m): return m.name
            }
        }
    }

    private var expenseCount: Int { store.categories.filter { $0.type == .expense }.count }
    private var incomeCount: Int { store.categories.filter { $0.type == .income }.count }

    var body: some View {
        NavigationView {
            Form {
                // 三个大类收进同一个分组，每个分组一个可折叠的头，默认全部收起
                Section(header: Text("分类管理"),
                        footer: Text("点开分组可查看、重命名或删除项目。在记账弹窗里现场输入的自定义项目，会随该笔账单保存后自动归到这里。")) {
                    groupHeader("支出项目", count: expenseCount, isExpanded: $expenseExpanded)
                    if expenseExpanded {
                        categoryRows(type: .expense)
                        addRow(placeholder: "新增支出项目", text: $newExpense) {
                            store.addCategory(name: newExpense, type: .expense)
                            newExpense = ""
                        }
                    }

                    groupHeader("收入项目", count: incomeCount, isExpanded: $incomeExpanded)
                    if incomeExpanded {
                        categoryRows(type: .income)
                        addRow(placeholder: "新增收入项目", text: $newIncome) {
                            store.addCategory(name: newIncome, type: .income)
                            newIncome = ""
                        }
                    }

                    groupHeader("支付方式", count: store.paymentMethods.count,
                                isExpanded: $paymentExpanded)
                    if paymentExpanded {
                        ForEach(store.paymentMethods) { m in
                            Text(m.name)
                                .modifier(ItemSwipeActions(
                                    delete: { store.deletePaymentMethod(m) },
                                    rename: { beginRename(.payment(m)) }
                                ))
                        }
                        addRow(placeholder: "新增支付方式", text: $newPayment) {
                            store.addPaymentMethod(name: newPayment)
                            newPayment = ""
                        }
                    }
                }

                Section(header: Text("数据"),
                        footer: Text("账本存在 App 沙盒内，卸载 App 会一并删除，建议定期导出备份。导入会整体替换当前账本，覆盖前会自动留一份备份文件。")) {
                    HStack {
                        Text("记录数")
                        Spacer()
                        Text("\(store.records.count) 条").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("账本文件")
                        Spacer()
                        Text(store.dataFileDescription).foregroundColor(.secondary)
                    }
                    if let warning = store.dataWarning {
                        Text(warning)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                    Button {
                        prepareExport()
                    } label: {
                        Label("导出账本 JSON", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        activeDataSheet = .importer
                    } label: {
                        Label("导入账本 JSON", systemImage: "square.and.arrow.down")
                    }
                    if let message = importMessage {
                        Text(message).font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("恢复预置项目")
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("设置")
            .sheet(item: $activeDataSheet) { sheet in
                switch sheet {
                case .share(let url):
                    ShareSheet(url: url)
                case .importer:
                    DocumentPicker { data in
                        do {
                            try store.importData(data)
                            importMessage = "导入成功：已替换当前账本，原账本已自动备份。"
                        } catch {
                            importMessage = "导入失败：\(error.localizedDescription)"
                        }
                        activeDataSheet = nil
                    }
                }
            }
            .alert("重命名", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("新名称", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("确定") { commitRename() }
            } message: {
                Text("原名称：\(renameTarget?.currentName ?? "")")
            }
            .alert("名称无效", isPresented: $showRenameError) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("名称不能为空，也不能与同类型的已有项目重名。")
            }
            .alert("恢复预置项目？", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("恢复", role: .destructive) {
                    store.resetToDefaults()
                }
            } message: {
                Text("自定义的项目与支付方式会被移除，已记录的账目不受影响。")
            }
        }
    }

    /// 折叠分组头：本身仍是 Form 里的一行，展开的项目行保持 List 上下文，
    /// 因此左滑重命名 / 删除照常生效。
    private func groupHeader(_ title: String, count: Int,
                             isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded.wrappedValue
                      ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .foregroundColor(.accentColor)
                    .imageScale(.small)
                Text(title).foregroundColor(.primary)
                Spacer(minLength: 8)
                Text("\(count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryRows(type: RecordType) -> some View {
        ForEach(store.categories.filter { $0.type == type }) { c in
            Text(c.name)
                .modifier(ItemSwipeActions(
                    delete: { store.deleteCategory(c) },
                    rename: { beginRename(.category(c)) }
                ))
        }
    }

    private func addRow(placeholder: String, text: Binding<String>,
                        action: @escaping () -> Void) -> some View {
        HStack {
            TextField(placeholder, text: text)
            Button("添加", action: action)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func prepareExport() {
        do {
            let data = try store.exportData()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmm"
            formatter.locale = Locale(identifier: "zh_CN")
            let name = "快捷记账-账本-\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            importMessage = nil
            activeDataSheet = .share(url)
        } catch {
            importMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func beginRename(_ target: RenameTarget) {
        renameText = target.currentName
        renameTarget = target
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let exists: Bool
        switch target {
        case .category(let c):
            // 只在同类型内查重：支出和收入允许各自叫「其他」。
            exists = store.categories.contains {
                $0.id != c.id && $0.type == c.type && $0.name == trimmed
            }
        case .payment(let m):
            exists = store.paymentMethods.contains { $0.id != m.id && $0.name == trimmed }
        }
        if trimmed.isEmpty || exists {
            showRenameError = true
            return
        }
        switch target {
        case .category(let c):
            store.renameCategory(c, to: trimmed)
        case .payment(let m):
            store.renamePaymentMethod(m, to: trimmed)
        }
        renameTarget = nil
    }
}

/// 列表项的滑动操作：重命名（蓝）+ 删除（红）。
private struct ItemSwipeActions: ViewModifier {
    let delete: () -> Void
    let rename: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: delete) {
                    Label("删除", systemImage: "trash")
                }
                Button(action: rename) {
                    Label("重命名", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }
}
