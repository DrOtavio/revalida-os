import Foundation

enum AppConfig {
    static let defaultDailyGoal = 80
    static let defaultSafetyTarget = 70

    static let remoteManifestURL =
        "https://drotavio.github.io/revalida-os/manifest.json"

    static var remoteContentBaseURL: URL? {
        guard let url = URL(string: remoteManifestURL) else { return nil }
        return url.deletingLastPathComponent()
    }

    static func resolveContentURL(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let absolute = URL(string: raw), absolute.scheme?.hasPrefix("http") == true {
            return absolute
        }
        guard let base = remoteContentBaseURL else { return nil }
        let clean = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        return URL(string: clean, relativeTo: base)?.absoluteURL
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
