import Foundation

enum AppConfig {
    static let defaultDailyGoal = 80
    static let defaultSafetyTarget = 70

    // Endpoint fixo do serviço de conteúdo. Não é editável pela interface.
    static let remoteManifestURL = "https://drotavio.github.io/revalida-os/manifest.json"
    static let allowedContentHost = "drotavio.github.io"
    static let allowedContentPathPrefix = "/revalida-os/"

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
