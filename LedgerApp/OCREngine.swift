import Foundation
import UIKit

/// 统一 OCR 入口：按用户在设置里选的模式，分发到本地识别或百度智能云。
/// 两个引擎都归一成 lines: [String]，调用方无需关心底层实现。
enum OCREngine {
    struct TextResult {
        let lines: [String]
        var fullText: String { lines.joined(separator: "\n") }
    }

    enum EngineError: LocalizedError {
        case missingCredentials
        var errorDescription: String? {
            "尚未填写百度智能云凭证。请到「设置 → OCR 识别」填写 API Key 和 Secret Key，或改用本地识别。"
        }
    }

    /// 识别图片。回调在主线程。
    static func recognize(image: UIImage, completion: @escaping (Result<TextResult, Error>) -> Void) {
        switch OCRConfig.mode {
        case .local:
            LocalOCR.recognize(image: image) { result in
                completion(result.map { TextResult(lines: $0.lines) })
            }
        case .baidu:
            guard OCRConfig.hasBaiduCredentials else {
                DispatchQueue.main.async { completion(.failure(EngineError.missingCredentials)) }
                return
            }
            BaiduOCR.recognize(image: image) { result in
                completion(result.map { TextResult(lines: $0.lines) })
            }
        }
    }
}
