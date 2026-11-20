import SwiftUI
import Foundation

struct AddRecordView: View {
    @EnvironmentObject var store: DataStore

    @State private var type: RecordType = .expense
    @State private var categoryName = ""
    @State private var amountText = ""
    @State private var paymentName = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var showSaved = false
    @State private var savedMessage = ""

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
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: type) { newValue in
                        categoryName = store.categories.first { $0.type == newValue }?.name ?? ""
                    }
                }

                Section(header: Text(type == .expense ? "支出项目" : "收入项目")) {
                    Picker("项目", selection: $categoryName) {
                        ForEach(availableCategories) { c in
                            Text("\(c.icon) \(c.name)").tag(c.name)
                        }
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
                    Picker("支付方式", selection: $paymentName) {
                        ForEach(store.paymentMethods) { m in
                            Text("\(m.icon) \(m.name)").tag(m.name)
                        }
                    }
                }

                Section(header: Text("日期")) {
                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("备注（可选）")) {
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
            .navigationTitle("记一笔")
            .onAppear(perform: setupDefaults)
            .alert(isPresented: $showSaved) {
                Alert(title: Text("已保存"), message: Text(savedMessage), dismissButton: .default(Text("好")))
            }
        }
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
        savedMessage = "\(type.rawValue) ¥\(String(format: "%.2f", amount)) 已记入「\(categoryName)」"
        showSaved = true
        amountText = ""
        note = ""
        date = Date()
    }
}
