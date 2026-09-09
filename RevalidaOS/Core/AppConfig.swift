import Foundation

enum AppConfig {
    static let defaultDailyGoal = 80
    static let defaultSafetyTarget = 70

    // Endpoint fixo do serviço de conteúdo. Não é editável pela interface.
    static let remoteManifestURL = "https://drotavio.github.io/revalida-os/manifest.json"
    static let allowedContentHost = "drotavio.github.io"
    static let allowedContentPathPrefix = "/revalida-os/"

    static var remoteContentBaseURL: URL? {
        guard let url = URL(string: remoteManifestURL) else { return nil }
        return url.deletingLastPathComponent()
    }

    static func resolveContentURL(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let resolved: URL?
        if let absolute = URL(string: raw), absolute.scheme?.hasPrefix("http") == true {
            resolved = absolute
        } else if let base = remoteContentBaseURL {
            let clean = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
            resolved = URL(string: clean, relativeTo: base)?.absoluteURL
        } else {
            resolved = nil
        }

        guard let url = resolved,
              url.scheme == "https",
              url.host?.lowercased() == allowedContentHost,
              url.path.hasPrefix(allowedContentPathPrefix) else {
            return nil
        }
        return url
    }

    static var dailyGoal: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "dailyGoal")
            return value > 0 ? value : defaultDailyGoal
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: "dailyGoal") }
    }

    static var safetyTarget: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "safetyTarget")
            return value > 0 ? value : defaultSafetyTarget
        }
        set { UserDefaults.standard.set(min(100, max(1, newValue)), forKey: "safetyTarget") }
    }
}
