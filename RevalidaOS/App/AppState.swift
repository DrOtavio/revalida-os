import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var unreadNewsCount = 0
    @Published var contentVersion = 0
    @Published var updateMessage: String?

    let store: SQLiteStore
    lazy var repository = AppRepository(store: store)
    lazy var updateService = ContentUpdateService(store: store)

    init() {
        do {
            store = try SQLiteStore()
        } catch {
            fatalError("Falha ao abrir banco local: \(error)")
        }
    }

    func bootstrap() async {
        do {
            try repository.prepareDatabase()
            try repository.importBundledSeedIfNeeded()
            contentVersion = repository.contentVersion()
            unreadNewsCount = repository.unreadNewsCount()
            isReady = true
            await checkForUpdates(silent: true)
        } catch {
            errorMessage = error.localizedDescription
            isReady = true
        }
    }

    func refreshBadges() {
        unreadNewsCount = repository.unreadNewsCount()
        contentVersion = repository.contentVersion()
    }

    func checkForUpdates(silent: Bool = false) async {
        do {
            let result = try await updateService.checkAndApplyUpdate(currentVersion: repository.contentVersion())
            switch result {
            case .upToDate:
                if !silent { updateMessage = "Banco já está atualizado." }
            case .updated(let version, let addedQuestions):
                updateMessage = "Banco atualizado para v\(version). +\(addedQuestions) questões."
                refreshBadges()
            case .notConfigured:
                if !silent { updateMessage = "URL remota ainda não configurada. O banco local continua funcionando normalmente." }
            }
        } catch {
            if !silent { updateMessage = "Não foi possível atualizar agora: \(error.localizedDescription)" }
        }
    }
}
