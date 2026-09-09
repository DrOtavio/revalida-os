import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var stats = DashboardStats(answeredToday: 0, dailyGoal: AppConfig.dailyGoal, totalAnswered: 0, scorableAnswered: 0, uniqueAnswered: 0, correctAnswered: 0, pendingReviews: 0, currentStreak: 0)
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                countdownCard
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Meta de hoje").font(.headline); Spacer(); Text("\(stats.answeredToday)/\(stats.dailyGoal)").font(.headline.monospacedDigit()) }
                    ProgressView(value: Double(stats.answeredToday), total: Double(max(1, stats.dailyGoal)))
                    Text(stats.answeredToday >= stats.dailyGoal ? "Meta batida. Próximo foco: revisão." : "Faltam \(max(0, stats.dailyGoal-stats.answeredToday)) questões.").font(.subheadline).foregroundStyle(.secondary)
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title:"Acerto geral", value:String(format:"%.1f%%", stats.accuracy), subtitle:"\(stats.scorableAnswered) respostas válidas", systemImage:"target")
                    MetricCard(title:"Questões únicas", value:"\(stats.uniqueAnswered)", subtitle:"\(stats.totalAnswered) respostas", systemImage:"square.stack.3d.up")
                    MetricCard(title:"Revisões", value:"\(stats.pendingReviews)", subtitle:"pendentes", systemImage:"arrow.triangle.2.circlepath")
                    MetricCard(title:"Sequência", value:"\(stats.currentStreak)d", subtitle:"dias consecutivos", systemImage:"flame.fill")
                }

                if let last = app.repository.latestSimulations(limit: 1).first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Último simulado").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(last.score)/\(last.total)").font(.largeTitle.bold())
                            Spacer()
                            if let cutoff = last.cutoff {
                                Label(last.score >= cutoff ? "Acima do corte" : "Abaixo do corte", systemImage: last.score >= cutoff ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").foregroundStyle(last.score >= cutoff ? .green : .orange)
                            }
                        }
                        if let cutoff = last.cutoff { Text("Corte da edição: \(cutoff) • margem: \(last.score-cutoff >= 0 ? "+" : "")\(last.score-cutoff)").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding()
        }
        .navigationTitle("Revalida OS")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    NewsCenterView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                        if app.unreadNewsCount > 0 {
                            Text(app.unreadNewsCount > 9 ? "9+" : "\(app.unreadNewsCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.red, in: Capsule())
                                .offset(x: 8, y: -7)
                        }
                    }
                }
                Button { showSettings = true } label: { Image(systemName:"gearshape.fill") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { stats = app.repository.dashboardStats(); app.refreshBadges() }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private var countdownCard: some View {
        let upcoming = app.repository.newsItems().filter { $0.eventDate != nil }.compactMap { item -> (NewsItem, Date)? in
            guard let value = item.eventDate, let date = Self.parseDate(value), date >= Calendar.current.startOfDay(for: Date()) else { return nil }
            return (item, date)
        }.sorted { $0.1 < $1.1 }.first
        return Group {
            if let upcoming {
                let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: upcoming.1).day ?? 0)
                VStack(alignment:.leading,spacing:8) {
                    Text(upcoming.0.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(upcoming.0.title).font(.title3.bold())
                    HStack(alignment:.lastTextBaseline) { Text("\(days)").font(.system(size:44,weight:.bold,design:.rounded)); Text(days == 1 ? "dia" : "dias").font(.title3); Spacer(); Image(systemName:"calendar.badge.clock").font(.title) }
                    Text("Próximo marco oficial").font(.caption).foregroundStyle(.secondary)
                }.padding().background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius:20))
            }
        }
    }
}


struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var goal = AppConfig.dailyGoal
    @State private var safety = AppConfig.safetyTarget

    var body: some View {
        NavigationStack {
            Form {
                Section("Metas") {
                    Stepper("Questões por dia: \(goal)", value: $goal, in: 1...500)
                    Stepper("Meta de segurança: \(safety)/100", value: $safety, in: 1...100)
                }

                Section("Atualização do banco") {
                    HStack {
                        Label("Fonte oficial configurada", systemImage: "lock.shield.fill")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    LabeledContent("Versão local", value: "v\(app.contentVersion)")
                    if let remote = app.remoteContentVersion {
                        LabeledContent("Versão remota", value: "v\(remote)")
                    }

                    Button {
                        Task { await app.checkForUpdates(silent: false) }
                    } label: {
                        HStack {
                            if app.isCheckingUpdate { ProgressView().controlSize(.small) }
                            Text(app.isCheckingUpdate ? "Verificando..." : "Verificar atualização")
                        }
                    }
                    .disabled(app.isCheckingUpdate)

                    if let msg = app.updateMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Text("O conteúdo oficial é atualizado por um endpoint fixo e validado pelo app. O endereço não pode ser alterado pelas configurações.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Configurações")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        AppConfig.dailyGoal = goal
                        AppConfig.safetyTarget = safety
                        dismiss()
                    }
                }
            }
        }
    }
}
