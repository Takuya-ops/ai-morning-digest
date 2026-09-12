import Foundation
import UIKit
import CryptoKit

actor ImageCache {
    static let shared = ImageCache()
    private var directory: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("digest-images", isDirectory: true) }
    private func path(_ url: URL) -> URL { directory.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()) }
    func image(_ url: URL) async -> Data? {
        let location = path(url)
        if let data = try? Data(contentsOf: location) { return data }
        guard url.scheme == "https" else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 3_000_000, UIImage(data: data) != nil else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: location, options: .atomic)
        return data
    }
    func prefetch(_ urls: [URL]) async {
        for url in Set(urls).prefix(40) { if Task.isCancelled { return }; _ = await image(url) }
        let old = Date().addingTimeInterval(-30 * 86400)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < old { try? FileManager.default.removeItem(at: file) }
        }
    }
}
