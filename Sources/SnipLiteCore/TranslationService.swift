import Foundation

public enum TranslationProviderKind: String, Codable, CaseIterable, Sendable {
    case google
    case myMemory
    case bingWeb
    case microsoft

    public var title: String {
        switch self {
        case .google: return "Google"
        case .myMemory: return "MyMemory"
        case .bingWeb: return "必应网页"
        case .microsoft: return "微软 Azure"
        }
    }

    /// 四家都接上了；Azure 需要在首选项里配置密钥。
    public var isAvailable: Bool { true }
}

public struct TranslationResult: Sendable {
    public let text: String
    public let detectedLanguage: String?

    public init(text: String, detectedLanguage: String?) {
        self.text = text
        self.detectedLanguage = detectedLanguage
    }
}

public enum TranslationError: LocalizedError {
    case emptyText
    case tooLong
    case unsupportedSource
    case sameLanguage
    case network
    case quota
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText: return "没有识别到可翻译的文字"
        case .tooLong: return "文字较多，请缩小选区后翻译"
        case .unsupportedSource: return "该翻译服务不支持自动检测语言"
        case .sameLanguage: return "源语言和目标语言相同"
        case .network: return "网络错误，请检查网络后重试"
        case .quota: return "翻译服务今日额度已用完"
        case .unavailable(let message): return message
        }
    }
}

public protocol TranslationProvider: AnyObject {
    var kind: TranslationProviderKind { get }
    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult
}

public enum TranslationServices {
    public static let maxCharacters = 12_000

    public static let languages: [(code: String, title: String)] = [
        ("auto", "自动检测"),
        ("en", "英语"),
        ("zh-CN", "简体中文"),
        ("zh-TW", "繁体中文"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语"),
        ("ru", "俄语"),
        ("it", "意大利语"),
        ("pt", "葡萄牙语")
    ]

    public static func title(for code: String) -> String {
        languages.first { $0.code == code }?.title ?? code
    }

    public static func make(_ kind: TranslationProviderKind) -> TranslationProvider {
        switch kind {
        case .google: return GoogleTranslationProvider()
        case .myMemory: return MyMemoryTranslationProvider()
        case .bingWeb: return BingWebTranslationProvider()
        case .microsoft: return AzureTranslationProvider()
        }
    }

    static func requestTimeout() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 35
        return URLSession(configuration: configuration)
    }
}

// MARK: - Google 公共接口

final class GoogleTranslationProvider: TranslationProvider {
    let kind: TranslationProviderKind = .google

    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard trimmed.count <= TranslationServices.maxCharacters else { throw TranslationError.tooLong }
        if source == target { return TranslationResult(text: text, detectedLanguage: source) }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
            URLQueryItem(name: "sl", value: source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components.url else { throw TranslationError.unavailable("翻译请求无效") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await TranslationServices.requestTimeout().data(from: url)
        } catch {
            throw TranslationError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranslationError.network }
        if http.statusCode == 429 { throw TranslationError.quota }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.unavailable("翻译服务暂时不可用（\(http.statusCode)）")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [[Any]] else {
            throw TranslationError.unavailable("翻译结果解析失败")
        }
        var translated = ""
        for segment in segments {
            if let piece = segment.first as? String { translated += piece }
        }
        guard !translated.isEmpty else { throw TranslationError.unavailable("翻译结果为空") }
        let detected = root.count > 2 ? root[2] as? String : nil
        return TranslationResult(text: translated, detectedLanguage: detected)
    }
}

// MARK: - MyMemory

final class MyMemoryTranslationProvider: TranslationProvider {
    let kind: TranslationProviderKind = .myMemory

    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard trimmed.count <= TranslationServices.maxCharacters else { throw TranslationError.tooLong }
        guard source != "auto" else { throw TranslationError.unsupportedSource }
        if source == target { return TranslationResult(text: text, detectedLanguage: source) }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "langpair", value: "\(source)|\(target)"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components.url else { throw TranslationError.unavailable("翻译请求无效") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await TranslationServices.requestTimeout().data(from: url)
        } catch {
            throw TranslationError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranslationError.network }
        if http.statusCode == 429 { throw TranslationError.quota }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.unavailable("翻译服务暂时不可用（\(http.statusCode)）")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.unavailable("翻译结果解析失败")
        }
        if let quota = root["quotaFinished"] as? Bool, quota {
            throw TranslationError.quota
        }
        guard let responseData = root["responseData"] as? [String: Any],
              let translated = responseData["translatedText"] as? String else {
            throw TranslationError.unavailable("翻译结果为空")
        }
        let decoded = translated
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return TranslationResult(text: decoded, detectedLanguage: source)
    }
}

final class UnavailableProvider: TranslationProvider {
    let kind: TranslationProviderKind

    init(kind: TranslationProviderKind) { self.kind = kind }

    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult {
        throw TranslationError.unavailable("\(kind.title) 将在后续阶段接入")
    }
}
