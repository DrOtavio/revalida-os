import SwiftUI

struct DiscursiveQuestionView: View {
    @EnvironmentObject var app: AppState
    let question: Question
    @State private var response = ""
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(question.area)
                        .font(.subheadline.bold())
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(question.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(question.stem)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sua resposta")
                        .font(.headline)
                    TextEditor(text: $response)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }

                if !revealed {
                    Button("Concluir e ver resposta oficial") {
                        revealed = true
                        app.repository.scheduleReview(questionId: question.id, reason: "discursive")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                } else {
                    Divider()
                    Text("Resposta oficial / padrão esperado")
                        .font(.title2.bold())
                    if let official = question.explanation, !official.isEmpty {
                        Text(official)
                            .textSelection(.enabled)
                    } else {
                        Text("A resposta oficial ainda não foi anexada a esta questão.")
                            .foregroundStyle(.secondary)
                    }
                    if let key = question.keyPoint, !key.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Critério-chave", systemImage: "checklist.checked")
                                .font(.headline)
                            Text(key)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(question.number.map { "Discursiva \($0)" } ?? "Discursiva")
        .navigationBarTitleDisplayMode(.inline)
    }
}
