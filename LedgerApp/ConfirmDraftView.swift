import SwiftUI

/// 粘贴板识别后的确认弹窗：展示识别结果 + 补全支出类型/方式/备注，确认后直接入账。
struct ConfirmDraftView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.presentationMode) var presentation

    let seed: ClipboardOCR.Draft

    @State private var amountText: String
    @State private var payee: String
    @State private var categoryName: String
    @State private var paymentName: String
    @State private var note: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var expenseCategories: [Category] { store.categories.filter { $0.type == .expense } }
    private var amount: Double { Double(amountText.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var canSave: Bool { amount > 0 && !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(seed: ClipboardOCR.Draft) {
        self.seed = seed
        _amountText = State(initialValue: seed.amount)
        _payee = State(initialValue: seed.payee)
        _categoryName = State(initialValue: "")
        _paymentName = State(initialValue: "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("识别结果（可修改）")) {
                    HStack {
                        Text("¥")
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    // 收款方未识别到时不显示这一行
                    if !seed.payee.isEmpty {
                        HStack {
                            Text("收款方").foregroundColor(.secondary)
                            TextField("收款方", text: $payee)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section(header: Text("支出类型（可手动输入）")) {
                    TextField("输入支出类型", text: $categoryName)
                    // 内置项快捷点按填入；手动输入的新类型在保存时加入内置项
                    Menu {
                        ForEach(expenseCategories) { c in
                            Button {
                                categoryName = c.name
                            } label: {
                                HStack {
                                    Text(c.name)
                                    if c.name == categoryName {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.2x2").foregroundColor(.accentColor)
                            Text("从内置项选择").foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary).imageScale(.small)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(header: Text("支出方式")) {
                    Menu {
                        ForEach(store.paymentMethods) { m in
                            Button {
                                paymentName = m.name
                            } label: {
                                HStack {
                                    Text(m.name)
                                    if m.name == paymentName {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "creditcard").foregroundColor(.accentColor)
                            Text(paymentName.isEmpty ? "请选择" : paymentName).foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary).imageScale(.small)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $note)
                }

                // 诊断区：显示识别原文与失败原因，便于核对金额/收款方为何未自动填入
                if !seed.errorMessage.isEmpty || !seed.rawText.isEmpty {
                    Section(header: Text("识别来源（供核对）")) {
                        if !seed.errorMessage.isEmpty {
                            Text(seed.errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        if !seed.rawText.isEmpty {
                            Text(seed.rawText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            Text("确认保存").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("识别确认")
            .navigationBarItems(leading: Button("取消") { presentation.wrappedValue.dismiss() })
            .onAppear(perform: setupDefaults)
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("好")))
            }
        }
    }

    private func setupDefaults() {
        if categoryName.isEmpty {
            categoryName = expenseCategories.first?.name ?? ""
        }
        if paymentName.isEmpty {
            paymentName = store.paymentMethods.first?.name ?? ""
        }
    }

    private func save() {
        guard amount > 0 else {
            alertMessage = "请输入有效金额"; showAlert = true; return
        }
        let typeName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typeName.isEmpty else {
            alertMessage = "请填写支出类型"; showAlert = true; return
        }
        // 手动输入的新支出类型：保存时加入内置项
        if !store.categories.contains(where: { $0.type == .expense && $0.name == typeName }) {
            store.addCategory(name: typeName, type: .expense)
        }
        let method = paymentName.isEmpty ? (store.paymentMethods.first?.name ?? "") : paymentName
        let record = Transaction(
            type: .expense,
            categoryName: typeName,
            amount: amount,
            paymentMethodName: method,
            date: Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addRecord(record)
        presentation.wrappedValue.dismiss()
    }
}
