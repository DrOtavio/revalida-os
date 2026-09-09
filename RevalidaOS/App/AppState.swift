import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var unreadNewsCount = 0
    @Published var contentVersion = 0
    @Published var remoteContentVersion: Int?
    @Published var updateMessage: String?
    @Published var isCheckingUpdate = false

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
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        if !silent {
            updateMessage = "Verificando servidor..."
        }
        defer { isCheckingUpdate = false }

        do {
            let result = try await updateService.checkAndApplyUpdate(currentVersion: repository.contentVersion())
            switch result {
            case .upToDate(let version):
                remoteContentVersion = version
                refreshBadges()
                if !silent {
                    updateMessage = "Banco já está atualizado. Local v\(contentVersion) • Remoto v\(version)."
                }

            case .updated(let version, let addedQuestions):
                remoteContentVersion = version
                refreshBadges()
                if addedQuestions > 0 {
                    updateMessage = "Banco atualizado para v\(version). +\(addedQuestions) questões."
                } else {
                    updateMessage = "Banco atualizado para v\(version). Conteúdo revisado sem novas questões."
                }

            case .notConfigured:
                if !silent {
                    updateMessage = "URL do banco não configurada."
                }
            }
        } catch {
            if !silent {
                updateMessage = "Falha na atualização: \(error.localizedDescription)"
            }
        }
    }
}
