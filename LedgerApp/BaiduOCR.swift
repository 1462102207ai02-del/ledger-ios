import Foundation
import UIKit

/// 百度智能云「通用文字识别（高精度版）」封装。
/// 流程：API Key/Secret 换取 access_token → base64 图片 POST 到 accurate_basic → 解析文字行。
enum BaiduOCR {
    // 测试版内置凭证（仅用于本地尝鲜，正式版不会包含）
    private static let apiKey = "JJFkaFv6Ze8lnmXJw6pSqzxe"
    private static let secretKey = "mwQEg1IfUeNvlxcbhxvizVzdxbKPLAQm"

    private static let tokenURL = "https://aip.baidubce.com/oauth/2.0/token"
    private static let recognizeURL = "https://aip.baidubce.com/rest/2.0/ocr/v1/accurate_basic"

    struct Result {
        let lines: [String]
        var fullText: String { lines.joined(separator: "\n") }
    }

    enum OCRFailure: LocalizedError {
        case token, network, parse(String)
        var errorDescription: String? {
            switch self {
            case .token: return "获取百度令牌失败，请检查网络与凭证"
            case .network: return "网络连接失败"
            case .parse(let m): return "识别失败：\(m)"
            }
        }
    }

    /// 主线程调用；网络请求在后台队列，结果回调回主线程。
    static func recognize(image: UIImage, completion: @escaping (Result<Result, Error>) -> Void) {
        guard let data = image.pngData() else {
            completion(.failure(OCRFailure.parse("图片无法读取"))); return
        }
        fetchToken { tokenResult in
            switch tokenResult {
            case .failure(let e):
                DispatchQueue.main.async { completion(.failure(e)) }
            case .success(let token):
                postImage(data, token: token) { imageResult in
                    DispatchQueue.main.async { completion(imageResult) }
                }
            }
        }
    }

    private static func fetchToken(_ completion: @escaping (Result<String, Error>) -> Void) {
        var comps = URLComponents(string: tokenURL)!
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: apiKey),
            URLQueryItem(name: "client_secret", value: secretKey)
        ]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                completion(.failure(OCRFailure.token)); return
            }
            completion(.success(token))
        }.resume()
    }

    private static func postImage(_ data: Data, token: String,
                                  _ completion: @escaping (Result<Result, Error>) -> Void) {
        let base64 = data.base64EncodedString()
        let body = "image=" + base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        var request = URLRequest(url: URL(string: "\(recognizeURL)?access_token=\(token)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                completion(.failure(OCRFailure.network)); return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                if let err = json["error_msg"] as? String, !err.isEmpty {
                    completion(.failure(OCRFailure.parse(err))); return
                }
                let rows = json["words_result"] as? [[String: Any]] ?? []
                let lines = rows.compactMap { $0["words"] as? String }
                completion(.success(Result(lines: lines)))
            } catch {
                completion(.failure(OCRFailure.parse("返回数据解析失败")))
            }
        }.resume()
    }
}

/// 从 OCR 文本里猜测账目字段：金额、项目、支付方式、日期。
/// 规则保守，宁可留空让用户填，也不乱猜。
enum OCRParser {
    struct Draft {
        var amount: String = ""
        var category: String = ""
        var payment: String = ""
        var note: String = ""
        var isIncome: Bool = false
    }

    static func parse(text: String, categories: [Category], payments: [PaymentMethod]) -> Draft {
        var d = Draft()
        let clean = text.replacingOccurrences(of: " ", with: "")

        // 金额：优先带 ¥ 的数字，其次出现「金额/合计/实付」附近的最大数字
        var candidates: [Double] = []
        let yenPattern = try? NSRegularExpression(pattern: "[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)")
        if let re = yenPattern {
            let ns = clean as NSString
            for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range(at: 1), in: clean),
                   let v = Double(clean[r]) { candidates.append(v) }
            }
        }
        if candidates.isEmpty {
            let plain = try? NSRegularExpression(pattern: "(?<![0-9])([0-9]{1,6}\\.[0-9]{2})(?![0-9])")
            if let re = plain {
                let ns = clean as NSString
                for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
                    if let r = Range(m.range(at: 1), in: clean),
                       let v = Double(clean[r]) { candidates.append(v) }
                }
            }
        }
        if let max = candidates.max() {
            d.amount = String(format: "%.2f", max)
        }

        // 支付方式：文本里出现哪个就算哪个
        for method in payments where clean.contains(method.name) {
            d.payment = method.name; break
        }

        // 项目：优先匹配用户自定义/内置项目名，其次常见商户关键词
        let merchantMap: [String: String] = [
            "星巴克": "饮料", "瑞幸": "饮料", "蜜雪": "饮料", "奶茶": "饮料", "咖啡": "饮料",
            "美团": "午餐", "饿了么": "午餐", "外卖": "午餐", "食堂": "午餐", "餐厅": "晚餐",
            "超市": "超市", "便利店": "饮料", "京东": "京东白条", "淘宝": "花呗", "天猫": "花呗",
            "滴滴": "跑腿", "出租": "跑腿", "加油": "信用卡"
        ]
        var matched = ""
        for cat in categories where clean.contains(cat.name) && cat.name.count >= 2 {
            matched = cat.name; break
        }
        if matched.isEmpty {
            for (keyword, catName) in merchantMap where clean.contains(keyword) {
                if categories.contains(where: { $0.name == catName }) { matched = catName; break }
            }
        }
        d.category = matched

        // 收入判断：出现「收款/入账/转账收入/工资」等
        let incomeWords = ["收款", "已入账", "收入", "工资", "货款到账"]
        d.isIncome = incomeWords.contains { clean.contains($0) }

        d.note = String(text.prefix(80))
        return d
    }
}
