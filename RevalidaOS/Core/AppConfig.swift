import Foundation

enum AppConfig {
    static let defaultDailyGoal = 80
    static let defaultSafetyTarget = 70

    // Endpoint oficial do conteúdo do Revalida OS.
    static let bundledRemoteManifestURL =
        "https://drotavio.github.io/revalida-os/manifest.json"

    static var remoteManifestURL: String {
        get {
            let saved = UserDefaults.standard
                .string(forKey: "remoteManifestURL")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? bundledRemoteManifestURL : saved
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(
                clean.isEmpty ? bundledRemoteManifestURL : clean,
                forKey: "remoteManifestURL"
            )
        }
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
