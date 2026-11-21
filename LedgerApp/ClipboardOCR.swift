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
        /// 粘贴板确实有可用内容（文字非空 / 有图片）。无内容时不弹窗。
        var hadContent: Bool = false
        /// OCR 失败的说明，供弹窗提示用户手动填写。
        var errorMessage: String = ""
    }

    /// 读取粘贴板并识别。图片走 OCR（异步），文字直接解析，结果回主线程。
    static func read(completion: @escaping (Draft) -> Void) {
        let pb = UIPasteboard.general
        if let image = pb.image {
            BaiduOCR.recognize(image: image) { result in
                var d = Draft()
                d.fromImage = true
                d.hadContent = true // 有截图，即便 OCR 失败也弹窗让用户手填
                switch result {
                case .success(let ocr):
                    d = parse(text: ocr.fullText)
                    d.fromImage = true
                    d.hadContent = true
                case .failure(let err):
                    d.errorMessage = "图片文字识别失败：\(err.localizedDescription)。请手动填写，或改用复制文字。"
                }
                DispatchQueue.main.async { completion(d) }
            }
        } else if let text = pb.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var d = parse(text: text)
            d.hadContent = true
            DispatchQueue.main.async { completion(d) }
        } else {
            DispatchQueue.main.async { completion(Draft()) }
        }
    }

    /// 只解析金额和收款方，其余字段一律不猜。
    static func parse(text: String) -> Draft {
        var d = Draft()
        d.rawText = String(text.prefix(200))
        let compact = text.replacingOccurrences(of: " ", with: "")

        // 金额候选，按可靠度分层，优先取 ¥/关键词 明确标注的数字，其次两位小数。
        var strong: [Double] = []   // ¥ 符号、金额类关键词、带「元」
        var weak: [Double] = []     // 孤立的两位小数

        func appendMatches(_ pattern: String, to bucket: inout [Double]) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let ns = compact as NSString
            for m in re.matches(in: compact, range: NSRange(location: 0, length: ns.length)) {
                // 取最后一个捕获组（各 pattern 都把数字放在捕获组里）
                let idx = m.numberOfRanges - 1
                guard idx > 0, let r = Range(m.range(at: idx), in: compact),
                      let v = Double(compact[r]) else { continue }
                bucket.append(v)
            }
        }

        appendMatches("[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)", to: &strong)
        appendMatches("(?:金额|实付|付款|支付|合计|总额|价格|收款)[:：为是]?([0-9]+(?:\\.[0-9]{1,2})?)", to: &strong)
        appendMatches("([0-9]+(?:\\.[0-9]{1,2})?)元", to: &strong)
        appendMatches("(?<![0-9])([0-9]{1,6}\\.[0-9]{2})(?![0-9])", to: &weak)

        if let max = (strong.isEmpty ? weak : strong).max() {
            d.amount = String(format: "%.2f", max)
        }

        // 收款方：常见标签后紧跟的名称，取到换行/空格/标点为止。
        let labels = ["收款商户名称", "收款商户", "商户名称", "收款方名称",
                      "收款方", "收款人", "商家名称", "商家", "商户", "付款给", "转账给"]
        for label in labels {
            guard let range = compact.range(of: label) else { continue }
            let tail = String(compact[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：·-— \n"))
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
