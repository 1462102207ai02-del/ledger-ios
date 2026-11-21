import Foundation
import UIKit

/// 粘贴板识别：读取粘贴板内容，只提取「金额」和「收款方」两项。
/// 草稿同时携带原文/原图，供确认页预览对照。
enum ClipboardOCR {
    struct Draft {
        var amount: String = ""
        var payee: String = ""
        /// 粘贴板文字原文，或截图 OCR 出的文字（用于预览核对）
        var rawText: String = ""
        /// 粘贴板里的图片（用于预览）
        var image: UIImage?
        var fromImage: Bool = false
        /// 粘贴板确实有内容（文字非空 / 有图片）。无内容时不弹窗。
        var hadContent: Bool = false
        /// OCR 失败说明
        var errorMessage: String = ""
    }

    /// 读取粘贴板并识别。图片走 OCR（异步），文字直接解析，结果回主线程。
    static func read(completion: @escaping (Draft) -> Void) {
        let pb = UIPasteboard.general
        let image = pb.image
        let text = pb.string

        if let image = image {
            OCREngine.recognize(image: image) { result in
                var d = Draft()
                d.image = image
                d.fromImage = true
                d.hadContent = true // 有截图就弹窗，即便 OCR 失败也让用户看原图手填
                switch result {
                case .success(let ocr):
                    d = parse(text: ocr.fullText)
                    d.image = image
                    d.fromImage = true
                    d.hadContent = true
                case .failure(let err):
                    d.errorMessage = "文字识别失败（\(OCRConfig.mode == .local ? "本地" : "百度智能云")）：\(err.localizedDescription)。下方原图可直接查看，请手动填写。"
                }
                DispatchQueue.main.async { completion(d) }
            }
        } else if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var d = parse(text: text)
            d.rawText = text             // 保留完整原文用于预览
            d.hadContent = true
            DispatchQueue.main.async { completion(d) }
        } else {
            DispatchQueue.main.async { completion(Draft()) }
        }
    }

    /// 全角数字/符号归一为半角，并去掉千分位逗号，方便正则匹配。
    private static func normalize(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            if v >= 0xFF10 && v <= 0xFF19 {           // ０-９
                scalars.append(UnicodeScalar(0x30 + (v - 0xFF10))!)
            } else if v == 0xFF0E {                   // ．
                scalars.append(UnicodeScalar(0x2E)!)
            } else if v == 0xFF1A {                   // ：
                scalars.append(UnicodeScalar(0x3A)!)
            } else if v == 0xFFE5 {                   // ￥
                scalars.append(UnicodeScalar(0xA5)!)
            } else if v == 0xFF0C {                   // ，
                scalars.append(UnicodeScalar(0x2C)!)
            } else {
                scalars.append(u)
            }
        }
        return String(String(scalars).replacingOccurrences(of: ",", with: ""))
    }

    /// 只解析金额和收款方，其余字段一律不猜。
    static func parse(text: String) -> Draft {
        var d = Draft()
        d.rawText = text
        let compact = normalize(text).replacingOccurrences(of: " ", with: "")
                       .replacingOccurrences(of: "\n", with: "")

        // 金额分层：strong 为带明确标识的数字，weak 为裸的两位小数。
        var strong: [Double] = []
        var weak: [Double] = []

        func matches(_ pattern: String, group: Int = 1, into bucket: inout [Double]) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let ns = compact as NSString
            for m in re.matches(in: compact, range: NSRange(location: 0, length: ns.length)) {
                let gi = min(group, m.numberOfRanges - 1)
                guard gi >= 0, let r = Range(m.range(at: gi), in: compact),
                      let v = Double(compact[r]) else { continue }
                bucket.append(v)
            }
        }

        // ¥28.00 / ￥28 / 28元 / 金额:28.5 / 实付28 / 支付¥28.00 / 交易金额28.00
        matches("[¥￥]([0-9]+(?:\\.[0-9]{1,2})?)", into: &strong)
        matches("(?:金额|实付|付款|支付|合计|总额|价格|收款|转账|消费|交易金额|订单金额)[:：为是]?[¥￥]?([0-9]+(?:\\.[0-9]{1,2})?)", into: &strong)
        matches("([0-9]+(?:\\.[0-9]{1,2})?)元", into: &strong)
        matches("(?<![0-9])([0-9]{1,6}\\.[0-9]{2})(?![0-9])", into: &weak)
        // 兜底：整段就是一个数字（如复制了「28」或「28.5」）
        if strong.isEmpty && weak.isEmpty, let v = Double(compact), v > 0 {
            strong.append(v)
        }

        if let max = (strong.isEmpty ? weak : strong).max() {
            d.amount = String(format: "%.2f", max)
        }

        // 收款方：常见标签后紧跟的名称。
        let labels = ["收款商户名称", "收款商户", "商户名称", "收款方名称", "商户全称",
                      "收款方", "收款人", "商家名称", "商家", "商户", "付款给", "转账给", "收款"]
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
