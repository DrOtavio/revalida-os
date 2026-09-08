import SwiftUI
import Charts

struct PerformanceView: View {
    @EnvironmentObject var app: AppState
    @State private var areas: [AreaPerformance] = []
    @State private var sims: [SimulationSummary] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if areas.isEmpty && sims.isEmpty {
                    ContentUnavailableView(
                        "Ainda sem dados",
                        systemImage: "chart.bar",
                        description: Text("Responda questões ou finalize um simulado para construir seus analytics.")
                    )
                }

                if !areas.isEmpty {
                    Text("Acerto por área")
                        .font(.title2.bold())

                    Chart(areas) { area in
                        BarMark(
                            x: .value("Acerto", area.percentage),
                            y: .value("Área", area.area)
                        )
                        .annotation(position: .trailing) {
                            Text(String(format: "%.0f%%", area.percentage))
                                .font(.caption)
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .frame(height: CGFloat(max(220, areas.count * 48)))

                    ForEach(areas.sorted { $0.percentage < $1.percentage }.prefix(3)) { area in
                        HStack {
                            Image(systemName: "scope")
                                .foregroundStyle(.orange)
                            Text("Prioridade: \(area.area)")
                            Spacer()
                            Text(String(format: "%.1f%%", area.percentage))
                                .bold()
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !sims.isEmpty {
                    Text("Evolução dos simulados")
                        .font(.title2.bold())

                    Chart {
                        ForEach(Array(sims.reversed().enumerated()), id: \.element.id) { index, simulation in
                            LineMark(
                                x: .value("Simulado", index + 1),
                                y: .value("Pontos", simulation.score)
                            )
                            PointMark(
                                x: .value("Simulado", index + 1),
                                y: .value("Pontos", simulation.score)
                            )
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 220)

                    ForEach(sims.prefix(5)) { simulation in
                        HStack {
                            Text(simulation.title)
                                .lineLimit(1)
                            Spacer()
                            Text("\(simulation.score)/\(simulation.total)")
                                .bold()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Desempenho")
        .onAppear {
            areas = app.repository.areaPerformance()
            sims = app.repository.latestSimulations(limit: 20)
        }
    }
}
