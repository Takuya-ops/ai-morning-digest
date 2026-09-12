import Foundation
import Security
import CryptoKit

struct XCredentials: Codable, Equatable {
    var apiKey = ""
    var apiSecret = ""
    var accessToken = ""
    var accessSecret = ""
    var bearerToken = ""
    var canPost: Bool { [apiKey, apiSecret, accessToken, accessSecret].allSatisfy { !$0.isEmpty } }
    var canRead: Bool { canPost || !bearerToken.isEmpty }
    func trimmed() -> Self { Self(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines), apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines), accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines), accessSecret: accessSecret.trimmingCharacters(in: .whitespacesAndNewlines), bearerToken: bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
enum XKeychain {
    private static let service = "com.takuyaops.aidigest.x"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "credentials"] }
    static func load() throws -> XCredentials {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return XCredentials() }
        guard status == errSecSuccess, let data = result as? Data else { throw XError.keychain }
        return try JSONDecoder().decode(XCredentials.self, from: data)
    }
    static func save(_ credentials: XCredentials) throws {
        let data = try JSONEncoder().encode(credentials.trimmed())
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw XError.keychain }
        } else if status != errSecSuccess { throw XError.keychain }
    }
    static func delete() throws { let result = SecItemDelete(query as CFDictionary); guard [errSecSuccess, errSecItemNotFound].contains(result) else { throw XError.keychain } }
}
enum XError: LocalizedError {
    case keychain, missingKeys, http(Int), malformed, invalidText, unknownOutcome
    var errorDescription: String? {
        switch self {
        case .keychain: return "認証情報を端末のKeychainで読み書きできませんでした。端末のロックを解除して再試行してください。"
        case .missingKeys: return "設定でX APIの認証情報を登録してください。投稿にはRead and write権限の4つのキーが必要です。"
        case .http(401): return "Xの認証に失敗しました。キーとアクセストークンを確認してください。"
        case .http(402): return "X APIのクレジットが不足しています。XのDeveloper Consoleをご確認ください。"
        case .http(403): return "この操作はXで許可されていません。APIのアクセス条件とRead and write権限を確認してください。"
        case .http(429): return "X APIの利用上限に達しました。時間をおいて再試行してください。"
        case .http(let status): return "X APIがエラーを返しました（HTTP \(status)）。自動再送は行いません。"
        case .malformed: return "Xから有効なデータを受け取れませんでした。"
        case .invalidText: return "投稿文を1〜280カウント以内にしてください。日本語は通常2カウントです。"
        case .unknownOutcome: return "通信が途中で切れたため投稿結果を確認できません。Xのプロフィールを確認してください。重複防止のため自動再送しません。"
        }
    }
}
enum OAuth1 {
    static func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))! }
    static func header(method: String, url: URL, credentials: XCredentials, nonce: String = UUID().uuidString, timestamp: String = String(Int(Date().timeIntervalSince1970))) -> String {
        var oauth = ["oauth_consumer_key": credentials.apiKey, "oauth_nonce": nonce, "oauth_signature_method": "HMAC-SHA1", "oauth_timestamp": timestamp, "oauth_token": credentials.accessToken, "oauth_version": "1.0"]
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        parts.query = nil; parts.fragment = nil
        let pairs: [(String, String)] = oauth.map { ($0.key, $0.value) } + query
        let encoded = pairs.map { (encode($0.0), encode($0.1)) }
        let sorted = encoded.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        let params = sorted.map { pair in "\(pair.0)=\(pair.1)" }.joined(separator: "&")
        let base = [method.uppercased(), parts.string!, params].map(encode).joined(separator: "&")
        let key = SymmetricKey(data: Data("\(encode(credentials.apiSecret))&\(encode(credentials.accessSecret))".utf8))
        oauth["oauth_signature"] = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(base.utf8), using: key)).base64EncodedString()
        return "OAuth " + oauth.sorted { $0.key < $1.key }.map { "\(encode($0.key))=\"\(encode($0.value))\"" }.joined(separator: ", ")
    }
}
// Count NFC Unicode with X's published weight ranges and 23-count web links.
// Foundation's link detector can differ at unusual URL boundaries; X validates on send.
enum XText {
    static func weight(_ text: String) -> Int {
        let value = text.precomposedStringWithCanonicalMapping
        let ns = value as NSString
        let links = (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?.matches(in: value, range: NSRange(location: 0, length: ns.length)).filter { ["https", "http"].contains($0.url?.scheme ?? "") } ?? []
        var offset = 0, count = 0
        for match in links { count += plain(ns.substring(with: NSRange(location: offset, length: match.range.location - offset))) + 23; offset = NSMaxRange(match.range) }
        return count + plain(ns.substring(from: offset))
    }
    private static func plain(_ text: String) -> Int {
        text.reduce(0) { sum, character in
            let scalars = character.unicodeScalars
            if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }) { return sum + 2 }
            return sum + scalars.reduce(0) { total, scalar in
                let n = scalar.value
                return total + ((n <= 0x10ff || (0x2000...0x200d).contains(n) || (0x2010...0x201f).contains(n) || (0x2032...0x2037).contains(n)) ? 1 : 2)
            }
        }
    }
    static func fit(_ text: String, budget: Int = 245) -> String {
        if weight(text) <= budget { return text }
        var result = ""
        for character in text { if weight(result + String(character) + "…") > budget { break }; result.append(character) }
        return result + "…"
    }
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct XAccount: Codable { let id: String; let name: String; let username: String }
final class XService {
    private let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral; config.httpShouldSetCookies = false; config.urlCache = nil; config.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, credentials: XCredentials, userContext: Bool = false) async throws -> Data {
        guard userContext ? credentials.canPost : credentials.canRead else { throw XError.missingKeys }
        var url = URLComponents(string: "https://api.x.com/2/\(path)")!; if !query.isEmpty { url.queryItems = query }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: url.url!); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = credentials.canPost ? OAuth1.header(method: method, url: url.url!, credentials: credentials) : "Bearer \(credentials.bearerToken)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw XError.malformed }
        guard (200...299).contains(response.statusCode) else { throw XError.http(response.statusCode) }
        return data
    }
    func account(credentials: XCredentials) async throws -> XAccount {
        struct Response: Decodable { let data: XAccount }
        return try JSONDecoder().decode(Response.self, from: await request(path: "users/me", credentials: credentials, userContext: true)).data
    }
    func search(query: String, credentials: XCredentials) async throws -> [XPost] {
        struct Tweet: Decodable { let id: String; let text: String; let author_id: String; let created_at: String }
        struct Includes: Decodable { let users: [XAccount]? }
        struct Response: Decodable { let data: [Tweet]?; let includes: Includes?; let meta: Meta?; struct Meta: Decodable { let result_count: Int } }
        let data = try await request(path: "tweets/search/recent", query: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "max_results", value: "10"), URLQueryItem(name: "tweet.fields", value: "created_at,author_id"), URLQueryItem(name: "expansions", value: "author_id"), URLQueryItem(name: "user.fields", value: "name,username"), URLQueryItem(name: "sort_order", value: "recency")], credentials: credentials)
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.data != nil || result.meta?.result_count == 0 else { throw XError.malformed }
        return (result.data ?? []).compactMap { tweet in
            guard let author = result.includes?.users?.first(where: { $0.id == tweet.author_id }) else { return nil }
            return XPost(id: tweet.id, text: tweet.text, username: author.username, name: author.name, createdAt: tweet.created_at)
        }
    }
    func post(text: String, credentials: XCredentials) async throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, XText.weight(text) <= 280, !text.unicodeScalars.contains(where: { [0xfffe, 0xfeff, 0xffff].contains($0.value) }) else { throw XError.invalidText }
        struct Response: Decodable { let data: Posted; struct Posted: Decodable { let id: String } }
        do {
            let data = try await request(path: "tweets", method: "POST", body: JSONSerialization.data(withJSONObject: ["text": text]), credentials: credentials, userContext: true)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.data.id.range(of: "^[0-9]+$", options: .regularExpression) != nil, let url = URL(string: "https://x.com/i/web/status/\(response.data.id)") else { throw XError.unknownOutcome }
            return url
        } catch let error as XError {
            if case .http(let status) = error, status >= 500 || status == 408 { throw XError.unknownOutcome }
            throw error
        } catch { throw XError.unknownOutcome }
    }
}
