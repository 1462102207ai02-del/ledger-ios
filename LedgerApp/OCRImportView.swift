import SwiftUI
import PhotosUI

/// 截图识别页：显示/选择支付截图 → 调百度 OCR → 展示可编辑草稿 → 填入记账表单。
struct OCRImportView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.presentationMode) var presentation

    @State private var image: UIImage?
    @State private var draft = OCRParser.Draft()
    @State private var busy = false
    @State private var message = ""
    @State private var showAlert = false
    @State private var showPicker = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    imageArea
                    if draft.amount.isEmpty {
                        Text("选择一张支付成功的截图，识别后金额、项目、支付方式会自动填入，确认无误再保存。")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        resultArea
                    }
                    if busy {
                        ProgressView("正在识别…")
                    }
                }
                .padding()
            }
            .navigationTitle("截图识别")
            .navigationBarItems(leading: Button("关闭") { presentation.wrappedValue.dismiss() })
            .sheet(isPresented: $showPicker) { PhotoPicker(image: $image) }
            .onAppear(perform: loadIncoming)
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(message), dismissButton: .default(Text("好")))
            }
        }
    }

    private var imageArea: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 320)
                    .cornerRadius(12)
            } else {
                Button {
                    showPicker = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34))
                        Text("选择支付截图").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(.systemGray6)).cornerRadius(12)
                }
            }
            HStack(spacing: 12) {
                if image != nil { Button("重选截图") { showPicker = true } }
                Button(image == nil ? "从相册选择" : "开始识别") {
                    if image == nil { showPicker = true } else { runOCR() }
                }
                .buttonStyle(.borderedProminent).disabled(busy)
            }
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("识别结果（可修改）").font(.headline)
            HStack {
                Text("类型"); Spacer()
                Picker("", selection: $draft.isIncome) {
                    Text("支出").tag(false); Text("收入").tag(true)
                }.pickerStyle(.segmented).frame(width: 180)
            }
            row("金额", text: $draft.amount, placeholder: "0.00", keyboard: .decimalPad)
            row("项目", text: $draft.category, placeholder: "如：午餐")
            row("支付方式", text: $draft.payment, placeholder: "如：微信")
            row("备注", text: $draft.note, placeholder: "可选")
            Button {
                commitDraft()
            } label: {
                HStack { Spacer(); Text("填入记账").fontWeight(.semibold); Spacer() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGray6)).cornerRadius(12)
    }

    private func row(_ title: String, text: Binding<String>, placeholder: String,
                     keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(title).frame(width: 72, alignment: .leading)
            TextField(placeholder, text: text).keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func loadIncoming() {
        guard let url = SharedStorage.sharedURL(for: SharedStorage.ocrImageName),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return }
        image = img
        // 读后即删，避免下次打开反复弹旧图
        try? FileManager.default.removeItem(at: url)
    }

    private func runOCR() {
        guard let img = image else { return }
        busy = true; message = ""
        BaiduOCR.recognize(image: img) { result in
            busy = false
            switch result {
            case .failure(let e):
                message = e.localizedDescription; showAlert = true
            case .success(let ocr):
                guard !ocr.lines.isEmpty else {
                    message = "没有识别到文字"; showAlert = true; return
                }
                draft = OCRParser.parse(text: ocr.fullText,
                                         categories: store.categories,
                                         payments: store.paymentMethods)
                if draft.amount.isEmpty {
                    message = "未识别到金额，请手动填写\n识别文字：\(ocr.fullText.prefix(120))"
                    showAlert = true
                }
            }
        }
    }

    private func commitDraft() {
        guard !draft.amount.isEmpty else {
            message = "请先填写金额"; showAlert = true; return
        }
        let payload = OCRDraft(amount: draft.amount, category: draft.category,
                               payment: draft.payment, note: draft.note, isIncome: draft.isIncome)
        if let url = SharedStorage.sharedURL(for: SharedStorage.ocrDraftName),
           let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
        presentation.wrappedValue.dismiss()
    }
}

// MARK: - 草稿模型（写入共享容器，记账页读取）
struct OCRDraft: Codable {
    var amount: String
    var category: String
    var payment: String
    var note: String
    var isIncome: Bool
}

// MARK: - 相册选择（PHPicker，iOS 15+，无需相册权限弹窗）
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentation

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentation.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { obj, _ in
                DispatchQueue.main.async { self.parent.image = obj as? UIImage }
            }
        }
    }
}
