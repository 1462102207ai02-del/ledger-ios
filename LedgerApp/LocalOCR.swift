import Foundation
import UIKit
import Vision

/// 本地 OCR：Apple Vision 框架，完全在设备端识别，离线、免费、不上传任何数据。
/// iOS 15 起 VNRecognizeTextRequest 原生支持简体中文。
enum LocalOCR {
    struct TextResult {
        let lines: [String]
        var fullText: String { lines.joined(separator: "\n") }
    }

    enum LocalError: LocalizedError {
        case noImage
        var errorDescription: String? { "图片无法读取，请换一张截图重试" }
    }

    /// 识别图片文字。回调固定切回主线程。
    static func recognize(image: UIImage, completion: @escaping (Result<TextResult, Error>) -> Void) {
        guard let cg = image.cgImage else {
            DispatchQueue.main.async { completion(.failure(LocalError.noImage)) }
            return
        }
        let request = VNRecognizeTextRequest { req, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async { completion(.success(TextResult(lines: lines))) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 简体中文 + 英文；iOS 15 的默认 revision 支持 zh-Hans
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
