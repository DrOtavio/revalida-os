import Foundation
import CryptoKit

enum UpdateResult {
    case upToDate(version: Int)
    case updated(version: Int, addedQuestions: Int)
    case notConfigured
}

final class ContentUpdateService {
    private let store: SQLiteStore

    init(store: SQLiteStore) {
        self.store = store
    }

    func checkAndApplyUpdate(currentVersion: Int) async throws -> UpdateResult {
        guard let baseManifestURL = URL(string: AppConfig.remoteManifestURL),
              isAllowedManifestURL(baseManifestURL) else {
            return .notConfigured
        }

        let manifestURL = cacheBustedURL(baseManifestURL)
        let manifestData = try await downloadNoCache(manifestURL)

        let manifest: ContentManifest
        do {
            manifest = try JSONDecoder().decode(ContentManifest.self, from: manifestData)
        } catch {
            throw UpdateError.invalidManifest
        }

        guard manifest.version > currentVersion else {
            return .upToDate(version: manifest.version)
        }

        guard let resolvedPackURL = URL(string: manifest.packURL, relativeTo: baseManifestURL)?.absoluteURL,
              isAllowedPackURL(resolvedPackURL) else {
            throw UpdateError.invalidPackURL
        }

        let packURL = cacheBustedURL(resolvedPackURL, version: manifest.version)
        let packData = try await downloadNoCache(packURL)

        if let expected = manifest.sha256, !expected.isEmpty {
            let digest = SHA256.hash(data: packData)
                .map { String(format: "%02x", $0) }
                .joined()
            guard digest.lowercased() == expected.lowercased() else {
                throw UpdateError.integrity
            }
        }

        let decodedPack: ContentPack
        do {
            decodedPack = try JSONDecoder().decode(ContentPack.self, from: packData)
        } catch {
            throw UpdateError.invalidPack
        }

        guard decodedPack.version == manifest.version else {
            throw UpdateError.versionMismatch(manifest: manifest.version, pack: decodedPack.version)
        }

        let before = questionCount()
        try AppRepository(store: store).importPack(data: packData)
        let persistedVersion = AppRepository(store: store).contentVersion()

        guard persistedVersion == manifest.version else {
            throw UpdateError.persistence(expected: manifest.version, found: persistedVersion)
        }

        let after = questionCount()
        return .updated(version: manifest.version, addedQuestions: max(0, after - before))
    }

    private func isAllowedManifestURL(_ url: URL) -> Bool {
        url.scheme == "https" &&
        url.host?.lowercased() == AppConfig.allowedContentHost &&
        url.path == "/revalida-os/manifest.json"
    }

    private func isAllowedPackURL(_ url: URL) -> Bool {
        url.scheme == "https" &&
        url.host?.lowercased() == AppConfig.allowedContentHost &&
        url.path.hasPrefix("/revalida-os/packs/") &&
        url.path.hasSuffix(".json")
    }

    private func questionCount() -> Int {
        let value = (try? store.query("SELECT COUNT(*) c FROM questions;").first?["c"]?.int) ?? 0
        return Int(value)
    }

    private func downloadNoCache(_ url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.noHTTPResponse }
        guard (200...299).contains(http.statusCode) else { throw UpdateError.httpStatus(http.statusCode) }
        guard let finalURL = http.url,
              finalURL.scheme == "https",
              finalURL.host?.lowercased() == AppConfig.allowedContentHost,
              finalURL.path.hasPrefix(AppConfig.allowedContentPathPrefix) else {
            throw UpdateError.untrustedRedirect
        }
        return data
    }

    private func cacheBustedURL(_ url: URL, version: Int? = nil) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "_cb" || $0.name == "_v" }
        if let version { items.append(URLQueryItem(name: "_v", value: String(version))) }
        items.append(URLQueryItem(name: "_cb", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url ?? url
    }
}

enum UpdateError: Error, LocalizedError {
    case integrity
    case invalidManifest
    case invalidPack
    case invalidPackURL
    case noHTTPResponse
    case httpStatus(Int)
    case untrustedRedirect
    case versionMismatch(manifest: Int, pack: Int)
    case persistence(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .integrity: return "Falha na verificação SHA-256 do pacote."
        case .invalidManifest: return "O manifest.json publicado não pôde ser interpretado."
        case .invalidPack: return "O pacote latest.json não pôde ser interpretado pelo app."
        case .invalidPackURL: return "O pacote aponta para uma origem não autorizada."
        case .noHTTPResponse: return "O servidor não retornou uma resposta HTTP válida."
        case .httpStatus(let code): return "O servidor respondeu HTTP \(code)."
        case .untrustedRedirect: return "A atualização tentou redirecionar para uma origem não autorizada."
        case .versionMismatch(let manifest, let pack): return "Versões inconsistentes: manifest v\(manifest), pack v\(pack)."
        case .persistence(let expected, let found): return "O banco foi baixado, mas a versão não persistiu (esperada v\(expected), encontrada v\(found))."
        }
    }
}
