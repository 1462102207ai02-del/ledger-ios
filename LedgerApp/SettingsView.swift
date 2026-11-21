import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore

    @State private var newExpense = ""
    @State private var newIncome = ""
    @State private var newPayment = ""
    @State private var showResetConfirm = false

    // OCR 识别配置（key 与 OCRConfig 保持一致，实时双向同步）
    @AppStorage("ocr.mode") private var ocrMode = "local"
    @AppStorage("ocr.baidu.apiKey") private var baiduAPIKey = ""
    @AppStorage("ocr.baidu.secretKey") private var baiduSecretKey = ""
    @AppStorage("ocr.baidu.model") private var baiduModel = "accurate_basic"

    // 重命名弹窗状态
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var showRenameError = false

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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OCR 识别"),
                        footer: Text("本地识别离线免费、不上传截图；百度智能云需自行填写凭证，识别更准但会联网上传。")) {
                    Picker("识别方式", selection: $ocrMode) {
                        Text("本地识别").tag("local")
                        Text("百度智能云").tag("baidu")
                    }
                    if ocrMode == "baidu" {
                        TextField("API Key", text: $baiduAPIKey)
                            .autocapitalization(.none).disableAutocorrection(true)
                        TextField("Secret Key", text: $baiduSecretKey)
                            .autocapitalization(.none).disableAutocorrection(true)
                        TextField("OCR 模型", text: $baiduModel)
                            .autocapitalization(.none).disableAutocorrection(true)
                        Text("模型为百度接口名，默认 accurate_basic（通用高精度版）")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("支出项目")) {
                    ForEach(store.categories.filter { $0.type == .expense }) { c in
                        Text(c.name)
                            .modifier(ItemSwipeActions(
                                delete: { store.deleteCategory(c) },
                                rename: { beginRename(.category(c)) }
                            ))
                    }
                    HStack {
                        TextField("新增支出项目", text: $newExpense)
                        Button("添加") {
                            store.addCategory(name: newExpense, type: .expense)
                            newExpense = ""
                        }
                        .disabled(newExpense.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section(header: Text("收入项目")) {
                    ForEach(store.categories.filter { $0.type == .income }) { c in
                        Text(c.name)
                            .modifier(ItemSwipeActions(
                                delete: { store.deleteCategory(c) },
                                rename: { beginRename(.category(c)) }
                            ))
                    }
                    HStack {
                        TextField("新增收入项目", text: $newIncome)
                        Button("添加") {
                            store.addCategory(name: newIncome, type: .income)
                            newIncome = ""
                        }
                        .disabled(newIncome.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section(header: Text("支付方式")) {
                    ForEach(store.paymentMethods) { m in
                        Text(m.name)
                            .modifier(ItemSwipeActions(
                                delete: { store.deletePaymentMethod(m) },
                                rename: { beginRename(.payment(m)) }
                            ))
                    }
                    HStack {
                        TextField("新增支付方式", text: $newPayment)
                        Button("添加") {
                            store.addPaymentMethod(name: newPayment)
                            newPayment = ""
                        }
                        .disabled(newPayment.trimmingCharacters(in: .whitespaces).isEmpty)
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
                Text("名称不能为空，也不能与已有项目重名。")
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
            exists = store.categories.contains { $0.id != c.id && $0.name == trimmed }
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
