import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if !app.isReady {
                VStack(spacing: 16) { ProgressView(); Text("Preparando banco local…").foregroundStyle(.secondary) }
            } else {
                TabView {
                    NavigationStack { HomeView() }.tabItem { Label("Início", systemImage: "house.fill") }
                    NavigationStack { QuestionBrowserView() }.tabItem { Label("Questões", systemImage: "checklist") }
                    NavigationStack { SimulationsView() }.tabItem { Label("Simulados", systemImage: "timer") }
                    NavigationStack { ReviewView() }.tabItem { Label("Revisão", systemImage: "arrow.clockwise") }
                    NavigationStack { PerformanceView() }.tabItem { Label("Desempenho", systemImage: "chart.xyaxis.line") }
                    NavigationStack { NewsCenterView() }
                        .tabItem { Label("Central", systemImage: "bell.fill") }
                        .badge(app.unreadNewsCount)
                }
            }
        }
        .alert("Revalida OS", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(app.errorMessage ?? "") }
    }
}
