import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// 截图分享扩展：接收系统分享面板里的图片，写入 App Group 共享容器，
/// 再通过 URL Scheme 拉起主 App 进入 OCR 识别页。
final class ShareViewController: SLComposeServiceViewController {
    private var handled = false

    override func isContentValid() -> Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 自动处理：快捷指令/相册分享图片进来后无需再点一次「发送」。
        // 稍作延迟，等输入项挂载完成再读取。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.didSelectPost()
        }
    }

    override func didSelectPost() {
        guard !handled else { finish(); return }
        handled = true
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            finish(); return
        }
        let imageType = UTType.image.identifier
        for provider in attachments
        where provider.hasItemConformingToTypeIdentifier(imageType) {
            provider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] obj, _ in
                guard let self = self else { return }
                let image = self.toUIImage(obj)
                if let image = image, let data = image.pngData(),
                   let url = SharedStorage.sharedURL(for: SharedStorage.ocrImageName) {
                    try? data.write(to: url, options: .atomic)
                    self.openHostApp()
                } else {
                    self.showAlert("未获取到可用图片")
                }
            }
            return
        }
        showAlert("未检测到图片")
    }

    override func configurationItems() -> [Any]! { [] }

    private func toUIImage(_ obj: Any?) -> UIImage? {
        if let img = obj as? UIImage { return img }
        if let data = obj as? Data { return UIImage(data: data) }
        if let url = obj as? URL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }

    private func openHostApp() {
        guard let url = URL(string: "ledgerocr://recognize") else { finish(); return }
        // 扩展里通过 extensionContext 打开宿主 App（UIApplication.shared 在扩展不可用）
        _ = extensionContext?.open(url, completionHandler: { [weak self] _ in
            self?.finish()
        })
        // 部分系统版本 open 回调不触发，兜底延迟结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.finish()
        }
    }

    private func showAlert(_ message: String) {
        let ac = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in self?.finish() })
        present(ac, animated: true)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
