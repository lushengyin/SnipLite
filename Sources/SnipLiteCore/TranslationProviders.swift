import Foundation
import Security

public enum Keychain {
    public static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public struct MicrosoftCredentials: Codable {
    public var key: String
    public var region: String

    private static let service = "com.sniplite.translator"
    private static let account = "microsoft"

    public init(key: String, region: String) {
        self.key = key
        self.region = region
    }

    public static func load() -> MicrosoftCredentials? {
        guard let data = Keychain.load(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(MicrosoftCredentials.self, from: data)
    }

    public static func save(_ credentials: MicrosoftCredentials?) {
        guard let credentials, !credentials.key.isEmpty else {
            Keychain.delete(service: service, account: account)
            return
        }
        if let data = try? JSONEncoder().encode(credentials) {
            Keychain.save(data, service: service, account: account)
        }
    }
}

// MARK: - 必应网页翻译

final class BingWebTranslationProvider: TranslationProvider {
    let kind: TranslationProviderKind = .bingWeb

    private struct Session {
        var key: String
        var token: String
        var ig: String
        var iid: String
        var expires: Date
    }

    private static var cachedSession: Session?
    private static let lock = NSLock()

    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard trimmed.count <= TranslationServices.maxCharacters else { throw TranslationError.tooLong }
        if source == target { return TranslationResult(text: text, detectedLanguage: source) }

        let session = try await ensureSession()

        var components = URLComponents(string: "https://cn.bing.com/ttranslatev3")!
        components.queryItems = [
            URLQueryItem(name: "isVertical", value: "1"),
            URLQueryItem(name: "IG", value: session.ig),
            URLQueryItem(name: "IID", value: session.iid)
        ]
        guard let url = components.url else { throw TranslationError.unavailable("翻译请求无效") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("https://cn.bing.com/translator", forHTTPHeaderField: "Referer")

        var body = [
            "text": trimmed,
            "fromLang": source == "auto" ? "auto-detect" : microsoftCode(source),
            "to": microsoftCode(target),
            "key": session.key,
            "token": session.token
        ]
        let encoded = body
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        request.httpBody = encoded.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await TranslationServices.requestTimeout().data(for: request)
        } catch {
            throw TranslationError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranslationError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            clearSession()
            throw TranslationError.unavailable("必应网页翻译会话失效，请重试")
        }
        if http.statusCode == 429 { throw TranslationError.quota }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.unavailable("必应网页翻译暂时不可用（\(http.statusCode)）")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = root.first,
              let translations = first["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw TranslationError.unavailable("必应翻译结果解析失败")
        }
        var detected: String?
        if let language = (first["detectedLanguage"] as? [String: Any])?["language"] as? String {
            detected = normalize(language)
        }
        return TranslationResult(text: translated, detectedLanguage: detected)
    }

    private func ensureSession() async throws -> Session {
        BingWebTranslationProvider.lock.lock()
        let cached = BingWebTranslationProvider.cachedSession
        BingWebTranslationProvider.lock.unlock()
        if let cached, cached.expires > Date() { return cached }
        return try await fetchSession()
    }

    private func fetchSession() async throws -> Session {
        guard let url = URL(string: "https://cn.bing.com/translator?setlang=zh-cn") else {
            throw TranslationError.unavailable("必应翻译地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            (data, _) = try await TranslationServices.requestTimeout().data(for: request)
        } catch {
            throw TranslationError.network
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw TranslationError.unavailable("必应网页解析失败")
        }

        guard let helper = firstMatch(in: html,
                                      pattern: #"params_AbusePreventionHelper\s*=\s*\[([0-9]+),\s*"([^"]+)""#),
              helper.count >= 2,
              let ig = firstCapture(in: html, pattern: #"IG:"([0-9A-Fa-f]+)""#),
              let iid = firstCapture(in: html, pattern: #"data-iid="([^"]+)""#) else {
            throw TranslationError.unavailable("必应网页未提供翻译会话")
        }

        let session = Session(key: helper[0], token: helper[1], ig: ig, iid: iid,
                              expires: Date().addingTimeInterval(300))
        BingWebTranslationProvider.lock.lock()
        BingWebTranslationProvider.cachedSession = session
        BingWebTranslationProvider.lock.unlock()
        return session
    }

    private func clearSession() {
        BingWebTranslationProvider.lock.lock()
        BingWebTranslationProvider.cachedSession = nil
        BingWebTranslationProvider.lock.unlock()
    }

    private func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) {
                groups.append(String(text[range]))
            }
        }
        return groups
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        firstMatch(in: text, pattern: pattern)?.first
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private func microsoftCode(_ code: String) -> String {
        switch code {
        case "zh-CN": return "zh-Hans"
        case "zh-TW": return "zh-Hant"
        default: return code
        }
    }

    private func normalize(_ code: String) -> String {
        switch code.lowercased() {
        case "zh-hans", "zh-cn": return "zh-CN"
        case "zh-hant", "zh-tw": return "zh-TW"
        default: return code
        }
    }
}

// MARK: - 微软 Azure

final class AzureTranslationProvider: TranslationProvider {
    let kind: TranslationProviderKind = .microsoft

    func translate(_ text: String, source: String, target: String) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard trimmed.count <= TranslationServices.maxCharacters else { throw TranslationError.tooLong }
        if source == target { return TranslationResult(text: text, detectedLanguage: source) }

        guard let credentials = MicrosoftCredentials.load() else {
            throw TranslationError.unavailable("请先在首选项 → 常规 里配置微软翻译密钥")
        }

        var components = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
        var items = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: microsoftCode(target))
        ]
        if source != "auto" {
            items.append(URLQueryItem(name: "from", value: microsoftCode(source)))
        }
        components.queryItems = items
        guard let url = components.url else { throw TranslationError.unavailable("翻译请求无效") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if !credentials.region.isEmpty {
            request.setValue(credentials.region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [["Text": trimmed]])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await TranslationServices.requestTimeout().data(for: request)
        } catch {
            throw TranslationError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranslationError.network }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw TranslationError.unavailable("密钥无效或配额不足，请检查密钥与区域")
        }
        if http.statusCode == 429 { throw TranslationError.quota }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationError.unavailable("微软翻译暂时不可用（\(http.statusCode)）")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = root.first,
              let translations = first["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw TranslationError.unavailable("微软翻译结果解析失败")
        }
        var detected: String?
        if let language = (first["detectedLanguage"] as? [String: Any])?["language"] as? String {
            detected = normalize(language)
        }
        return TranslationResult(text: translated, detectedLanguage: detected)
    }

    private func microsoftCode(_ code: String) -> String {
        switch code {
        case "zh-CN": return "zh-Hans"
        case "zh-TW": return "zh-Hant"
        default: return code
        }
    }

    private func normalize(_ code: String) -> String {
        switch code.lowercased() {
        case "zh-hans", "zh-cn": return "zh-CN"
        case "zh-hant", "zh-tw": return "zh-TW"
        default: return code
        }
    }
}
