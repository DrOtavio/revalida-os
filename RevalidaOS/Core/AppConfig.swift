import Foundation

enum AppConfig {
    static let defaultDailyGoal = 80
    static let defaultSafetyTarget = 70

    // Troque por uma URL HTTPS estável do seu repositório de conteúdo antes do build final.
    // Também pode ser alterada dentro do app em Início > Configurações do banco.
    static let bundledRemoteManifestURL = ""

    static var remoteManifestURL: String {
        get { UserDefaults.standard.string(forKey: "remoteManifestURL") ?? bundledRemoteManifestURL }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "remoteManifestURL") }
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
