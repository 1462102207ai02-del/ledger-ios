import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore

    @State private var newExpense = ""
    @State private var newIncome = ""
    @State private var newPayment = ""
    @State private var showResetConfirm = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("支出项目")) {
                    ForEach(store.categories.filter { $0.type == .expense }) { c in
                        Text(c.name)
                    }
                    .onDelete { idx in
                        let list = store.categories.filter { $0.type == .expense }
                        for i in idx { store.deleteCategory(list[i]) }
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
                    }
                    .onDelete { idx in
                        let list = store.categories.filter { $0.type == .income }
                        for i in idx { store.deleteCategory(list[i]) }
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
                    }
                    .onDelete { idx in
                        for i in idx { store.deletePaymentMethod(store.paymentMethods[i]) }
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
}
