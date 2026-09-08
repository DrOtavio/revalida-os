import SwiftUI

struct NewsCenterView: View {
    @EnvironmentObject var app: AppState
    @State private var items: [NewsItem] = []
    @State private var alertStatus: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        let ok = await NotificationScheduler.requestAndSchedule(items: items)
                        alertStatus = ok ? "Alertas locais ativados para os próximos prazos." : "Permissão de notificações não concedida."
                    }
                } label: {
                    Label("Ativar alertas de prazos", systemImage: "bell.badge.fill")
                }
                if let alertStatus {
                    Text(alertStatus).font(.footnote).foregroundStyle(.secondary)
                }
            }

            ForEach(items) { item in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.category.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(priorityColor(item.priority))
                            Spacer()
                            if let event = item.eventDate {
                                Text(format(event)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(item.title).font(.headline)
                        Text(item.body).foregroundStyle(.secondary)
                        if let end = item.endDate {
                            Label("Prazo até \(format(end))", systemImage: "hourglass.bottomhalf.filled")
                                .font(.subheadline)
                        }
                        if let raw = item.sourceURL, let url = URL(string: raw) {
                            Link(destination: url) {
                                Label("Fonte oficial", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Central Revalida")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Marcar lidas") {
                    app.repository.markAllNewsRead()
                    app.refreshBadges()
                    items = app.repository.newsItems()
                }
            }
        }
        .onAppear {
            items = app.repository.newsItems()
            app.repository.markAllNewsRead()
            app.refreshBadges()
        }
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "urgent": return .red
        case "high": return .orange
        default: return .accentColor
        }
    }

    private func format(_ s: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
