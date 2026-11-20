import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore

    @State private var newExpense = ""
    @State private var newIncome = ""
    @State private var newPayment = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("支出项目")) {
                    ForEach(store.categories.filter { $0.type == .expense }) { c in
                        HStack {
                            Text(c.icon)
                            Text(c.name)
                            Spacer()
                            if c.isBuiltIn {
                                Text("预置").font(.caption).foregroundColor(.secondary)
                            }
                        }
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
                        HStack {
                            Text(c.icon)
                            Text(c.name)
                            Spacer()
                            if c.isBuiltIn {
                                Text("预置").font(.caption).foregroundColor(.secondary)
                            }
                        }
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
                        HStack {
                            Text(m.icon)
                            Text(m.name)
                        }
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
                    Button("恢复预置项目") {
                        store.resetToDefaults()
                    }
                    .foregroundColor(.orange)
                } footer: {
                    Text("数据仅保存在本机 App 沙盒中，卸载 App 会一并删除。")
                }
            }
            .navigationTitle("设置")
        }
    }
}
