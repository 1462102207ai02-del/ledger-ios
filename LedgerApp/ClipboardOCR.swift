import Foundation
import UIKit

/// 粘贴板识别：读取粘贴板内容，只提取「金额」和「收款方」两项。
/// 粘贴板若为图片则走百度 OCR 转文字，若为纯文本则直接解析。
enum ClipboardOCR {
    struct Draft {
        var amount: String = ""
        var payee: String = ""
        var rawText: String = ""
        var fromImage: Bool = false

        var isEmpty: Bool { amount.isEmpty && payee.isEmpty }
    }

    /// 读取粘贴板并识别。图片走 OCR（异步），文字直接解析，结果回主线程。
    static func read(completion: @escaping (Draft) -> Void) {
        let pb = UIPasteboard.general
        if let image = pb.image {
            BaiduOCR.recognize(image: image) { result in
                switch result {
                case .success(let ocr):
                    var d = parse(text: ocr.fullText)
                    d.fromImage = true
                    DispatchQueue.main.async { completion(d) }
                case .failure:
                    DispatchQueue.main.async { completion(Draft(fromImage: true)) }
                }
            }
        } else if let text = pb.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var d = parse(text: text)
            d.rawText = String(text.prefix(160))
            DispatchQueue.main.async { completion(d) }
        } else {
            DispatchQueue.main.async { completion(Draft()) }
        }
    }

    /// 只解析金额和收款方，其余字段一律不猜。
    static func parse(text: String) -> Draft {
        var d = Draft()
        d.rawText = String(text.prefix(160))
        let compact = text.replacingOccurrences(of: " ", with: "")

        // 金额：优先带 ¥/￥ 的数字，其次出现 x.xx 形式，取候选中的最大值。
        var candidates: [Double] = []
        if let re = try? NSRegularExpression(pattern: "[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)") {
            let ns = compact as NSString
            for m in re.matches(in: compact, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range(at: 1), in: compact),
                   let v = Double(compact[r]) { candidates.append(v) }
            }
        }
        if candidates.isEmpty,
           let re = try? NSRegularExpression(pattern: "(?<![0-9])([0-9]{1,6}\\.[0-9]{2})(?![0-9])") {
            let ns = compact as NSString
            for m in re.matches(in: compact, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range(at: 1), in: compact),
                   let v = Double(compact[r]) { candidates.append(v) }
            }
        }
        if let max = candidates.max() { d.amount = String(format: "%.2f", max) }

        // 收款方：常见标签后紧跟的名称，取到换行/空格/标点为止。
        let labels = ["收款商户名称", "收款商户", "商户名称", "收款方名称",
                      "收款方", "收款人", "商家名称", "商家", "商户", "付款给", "转账给"]
        for label in labels {
            guard let range = compact.range(of: label) else { continue }
            let tail = String(compact[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：·-— "))
            var name = ""
            for ch in tail {
                if ch.isWhitespace || ch == "¥" || ch == "￥" || ch == "(" || ch == "（"
                    || ch == ":" || ch == "：" || ch == "," || ch == "，"
                    || ch == "-" || ch == "—" { break }
                name.append(ch)
                if name.count >= 24 { break }
            }
            if !name.isEmpty { d.payee = name; break }
        }
        return d
    }
}
