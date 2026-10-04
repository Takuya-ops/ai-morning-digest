import Foundation
import CryptoKit
import Network

enum BriefingVoice: String, CaseIterable, Identifiable {
    case gemini = "gemini-3.8-flash-tts-Kore"
    case nanami = "ja-JP-NanamiNeural"
    case keita = "ja-JP-KeitaNeural"
    case device
    var id: String { rawValue }
    var label: String { switch self { case .gemini: return "Gemini 3.8（Kore）"; case .nanami: return "Microsoft Nanami（女性）"; case .keita: return "Microsoft Keita（男性）"; case .device: return "iPhoneの標準音声" } }
    var shortName: String { switch self { case .gemini: return "Gemini 3.8"; case .nanami: return "Nanami"; case .keita: return "Keita"; case .device: return "iPhone標準" } }
}
actor AudioCache {
    static let shared = AudioCache()
    private let directory: URL
    private let session: URLSession
    private var protectedURL: URL?
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pins: Set<String> = []
    private var pinsLoaded = false
    private func loadPins() {
        if !pinsLoaded { pins = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: directory.appendingPathComponent("pins.json")))) ?? []; pinsLoaded = true }
    }
    private func name(_ url: URL) -> String { SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + (url.pathExtension.lowercased() == "wav" ? ".wav" : ".mp3") }
    private func acquire() async { if active < 2 { active += 1; return }; await withCheckedContinuation { waiters.append($0) } }
    private func release() { if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() } }
    func protect(_ url: URL?) { protectedURL = url }
    func pin(_ url: URL, value: Bool) throws {
        loadPins(); if value { pins.insert(name(url)) } else { pins.remove(name(url)) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(pins).write(to: directory.appendingPathComponent("pins.json"), options: .atomic)
    }
    func usage() -> (bytes: Int, pinned: Int) {
        loadPins(); let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return (files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }, pins.count)
    }
    func discardDownload(_ url: URL) {
        try? pin(url, value: false)
        if url != protectedURL { invalidate(url) }
    }
    func removeDownloads() {
        loadPins(); pins = []; try? JSONEncoder().encode(pins).write(to: directory.appendingPathComponent("pins.json"), options: .atomic)
        let protected = protectedURL.map(name)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where file.lastPathComponent != protected && file.pathExtension != "json" { try? FileManager.default.removeItem(at: file) }
    }
    func verifiedFile(for url: URL, metadata: AudioMetadata?) async throws -> URL {
        let location = try await file(for: url)
        if let metadata {
            let bytes = try Data(contentsOf: location)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard bytes.count == metadata.byteLength, hash == metadata.assetSHA256 else { invalidate(url); throw URLError(.cannotDecodeContentData) }
        }
        return location
    }
    private var inFlight: [URL: Task<URL, Error>] = [:]
    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("briefing-audio", isDirectory: true)
        self.session = session
    }
    func file(for url: URL) async throws -> URL {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + (url.pathExtension.lowercased() == "wav" ? ".wav" : ".mp3")
        let location = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: location.path) { try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: location.path); return location }
        if let existing = inFlight[url] { return try await existing.value }
        let task = Task<URL, Error> {
            await self.acquire(); defer { self.release() }
            try Task.checkCancellation()
            var request = URLRequest(url: url); request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, (500...32_000_000).contains(data.count) else { throw URLError(.badServerResponse) }
            let header = Array(data.prefix(3))
            let isWAV = data.prefix(4) == Data("RIFF".utf8) && data.subdata(in: 8..<12) == Data("WAVE".utf8)
            let isMP3 = header == [0x49, 0x44, 0x33] || (header[0] == 0xff && header[1] & 0xe0 == 0xe0)
            guard url.pathExtension.lowercased() == "wav" ? isWAV : isMP3 else { throw URLError(.cannotDecodeContentData) }
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.prune(reserving: data.count)
            guard self.usage().bytes + data.count <= 250 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            try data.write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return location
        }
        inFlight[url] = task; defer { inFlight[url] = nil }
        return try await task.value
    }
    func invalidate(_ url: URL) {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + (url.pathExtension.lowercased() == "wav" ? ".wav" : ".mp3")
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
    func prefetch(_ urls: [URL]) async {
        guard await NetworkPolicy.onWiFi() else { return }
        for url in Set(urls).prefix(12) { guard !Task.isCancelled else { return }; _ = try? await file(for: url) }
    }
    func prune(reserving: Int = 0) {
        loadPins()
        let cutoff = Date().addingTimeInterval(-7 * 86400), protected = protectedURL.map(name)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []).filter { $0.pathExtension != "json" }.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var bytes = usage().bytes
        for file in files where !pins.contains(file.lastPathComponent) && file.lastPathComponent != protected {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if (values?.contentModificationDate ?? .distantPast) < cutoff || bytes + reserving > 250 * 1024 * 1024 {
                do { try FileManager.default.removeItem(at: file); bytes -= values?.fileSize ?? 0 } catch {}
            }
        }
    }
}
enum NetworkPolicy {
    static func onWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in monitor.cancel(); continuation.resume(returning: path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive && !path.isConstrained) }
            monitor.start(queue: DispatchQueue(label: "digest.network-check"))
        }
    }
}
