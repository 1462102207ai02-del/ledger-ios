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
                Section {
                    Button {
                        NotificationCenter.default.post(name: .openOCR, object: nil)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder").foregroundColor(.accentColor)
                            Text("截图识别记账").foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                    }
                }
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

                Section(header: Text(type == .expense ? "支出项目" : "收入项目")) {
                    selectionMenu(title: categoryName, options: availableCategories.map(\.name),
                                  systemImage: "square.grid.2x2") { name in
                        categoryName = name
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
                    selectionMenu(title: paymentName, options: store.paymentMethods.map(\.name),
                                  systemImage: "creditcard") { name in
                        paymentName = name
                    }
                }

                Section(header: Text("日期")) {
                    DatePicker("日期", selection: $date, displayedComponents: [.date])
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
            .onAppear(perform: setupDefaults)
            .alert(isPresented: $showSaved) {
                Alert(title: Text("已保存"), message: Text(savedMessage), dismissButton: .default(Text("好")))
            }
        }
    }

    /// 扁平选择按钮：浅灰圆角行内显示图标与当前选中项，点按弹出菜单选择。
    private func selectionMenu(title: String, options: [String], systemImage: String,
                               onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(option)
                        if option == title {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                Text(title.isEmpty ? "请选择" : title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
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
        if let draft = loadDraft() {
            // 来自截图识别的草稿：填入并可继续编辑，确认后由用户点保存
            type = draft.isIncome ? .income : .expense
            if !draft.category.isEmpty { categoryName = draft.category }
            if !draft.payment.isEmpty { paymentName = draft.payment }
            if !draft.amount.isEmpty { amountText = draft.amount }
            if !draft.note.isEmpty { note = draft.note }
        }
        if categoryName.isEmpty {
            categoryName = availableCategories.first?.name ?? ""
        }
        if paymentName.isEmpty {
            paymentName = store.paymentMethods.first?.name ?? ""
        }
    }

    /// 读取截图识别草稿，读后即删，避免重复填充。
    private func loadDraft() -> OCRDraft? {
        guard let url = SharedStorage.sharedURL(for: SharedStorage.ocrDraftName),
              let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(OCRDraft.self, from: data) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return draft
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
