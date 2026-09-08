import Foundation
import CryptoKit

enum UpdateResult { case upToDate, updated(version: Int, addedQuestions: Int), notConfigured }

final class ContentUpdateService {
    private let store: SQLiteStore
    init(store: SQLiteStore) { self.store = store }

    func checkAndApplyUpdate(currentVersion: Int) async throws -> UpdateResult {
        let raw = AppConfig.remoteManifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme == "https" else { return .notConfigured }
        let (manifestData, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: manifestData)
        guard manifest.version > currentVersion else { return .upToDate }
        guard let packURL = URL(string: manifest.packURL, relativeTo: url)?.absoluteURL else { throw URLError(.badURL) }
        let (packData, packResponse) = try await URLSession.shared.data(from: packURL)
        guard (packResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        if let expected = manifest.sha256, !expected.isEmpty {
            let digest = SHA256.hash(data: packData).map { String(format: "%02x", $0) }.joined()
            guard digest.lowercased() == expected.lowercased() else { throw UpdateError.integrity }
        }
        let before = (try? store.query("SELECT COUNT(*) c FROM questions;").first?["c"]?.int).flatMap(Int.init) ?? 0
        try AppRepository(store: store).importPack(data: packData)
        let after = (try? store.query("SELECT COUNT(*) c FROM questions;").first?["c"]?.int).flatMap(Int.init) ?? before
        return .updated(version: manifest.version, addedQuestions: max(0, after-before))
    }
}

enum UpdateError: Error, LocalizedError {
    case integrity
    var errorDescription: String? { "Falha na verificação de integridade do pacote." }
}
