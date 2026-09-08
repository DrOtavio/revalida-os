import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var app: AppState
    @State private var pending: [Question] = []
    @State private var all: [Question] = []

    var body: some View {
        List {
            Section("Para hoje") {
                if pending.isEmpty {
                    ContentUnavailableView(
                        "Sem revisões vencidas",
                        systemImage: "checkmark.circle",
                        description: Text("As questões erradas e marcadas aparecem aqui.")
                    )
                } else {
                    ForEach(pending) { q in
                        NavigationLink {
                            StudyQuestionView(question: q)
                        } label: {
                            row(q)
                        }
                    }
                }
            }

            Section("Fila completa — \(all.count)") {
                ForEach(all) { q in
                    NavigationLink {
                        StudyQuestionView(question: q)
                    } label: {
                        row(q)
                    }
                }
            }
        }
        .navigationTitle("Revisão")
        .onAppear {
            pending = app.repository.pendingReviewQuestions()
            all = app.repository.allReviewQuestions()
        }
    }

    private func row(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q.area)
                .font(.caption.bold())
                .foregroundStyle(.tint)
            Text(q.stem)
                .lineLimit(2)
        }
    }
}
