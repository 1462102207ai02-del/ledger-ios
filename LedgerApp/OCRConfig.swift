import Foundation

/// OCR 识别配置：识别引擎（本地 / 百度智能云）与百度凭证。
/// 用 UserDefaults.standard 存储，设置页通过 @AppStorage 绑定相同 key，双向同步。
enum OCRConfig {
    // MARK: - 存储 key（设置页 @AppStorage 必须使用完全相同的字符串）
    static let modeKey = "ocr.mode"            // "local" / "baidu"
    static let apiKeyKey = "ocr.baidu.apiKey"
    static let secretKeyKey = "ocr.baidu.secretKey"
    static let modelKey = "ocr.baidu.model"    // 百度接口名，如 accurate_basic

    static let defaultModel = "accurate_basic"

    enum Mode: String {
        case local
        case baidu
    }

    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .local }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var apiKey: String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    static var secretKey: String {
        UserDefaults.standard.string(forKey: secretKeyKey) ?? ""
    }

    static var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    /// 百度凭证是否齐全
    static var hasBaiduCredentials: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
