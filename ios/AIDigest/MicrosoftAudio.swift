import Foundation
import CryptoKit

enum BriefingVoice: String, CaseIterable, Identifiable {
    case nanami = "ja-JP-NanamiNeural"
    case keita = "ja-JP-KeitaNeural"
    case device
    var id: String { rawValue }
    var label: String { switch self { case .nanami: return "Microsoft Nanami（女性）"; case .keita: return "Microsoft Keita（男性）"; case .device: return "iPhoneの標準音声" } }
    var shortName: String { switch self { case .nanami: return "Nanami"; case .keita: return "Keita"; case .device: return "iPhone標準" } }
}
actor AudioCache {
    static let shared = AudioCache()
    private let directory: URL
    private let session: URLSession
    private var inFlight: [URL: Task<URL, Error>] = [:]
    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("briefing-audio", isDirectory: true)
        self.session = session
    }
    func file(for url: URL) async throws -> URL {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".mp3"
        let location = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: location.path) { return location }
        if let existing = inFlight[url] { return try await existing.value }
        let task = Task<URL, Error> {
            var request = URLRequest(url: url); request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, (500...8_000_000).contains(data.count) else { throw URLError(.badServerResponse) }
            let header = Array(data.prefix(3))
            guard header == [0x49, 0x44, 0x33] || (header[0] == 0xff && header[1] & 0xe0 == 0xe0) else { throw URLError(.cannotDecodeContentData) }
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return location
        }
        inFlight[url] = task; defer { inFlight[url] = nil }
        return try await task.value
    }
    func invalidate(_ url: URL) {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".mp3"
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
    func prefetch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in Set(urls).prefix(12) { group.addTask { _ = try? await self.file(for: url) } }
        }
    }
    func prune() {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}
