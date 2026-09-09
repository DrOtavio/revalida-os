import SwiftUI

struct QuestionBrowserView: View {
    @EnvironmentObject var app: AppState
    @State private var area = "Todas"
    @State private var questions: [Question] = []
    @State private var selectedQuestion: Question?

    var body: some View {
        List {
            Section {
                Picker("Área", selection: $area) {
                    ForEach(areas, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: area) { _, _ in reload() }
            }

            Section("Banco — \(questions.count) questões") {
                ForEach(questions) { q in
                    Button { selectedQuestion = q } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.displayTopic)
                                        .font(.caption.bold())
                                        .foregroundStyle(.tint)
                                    Text(q.displayCategory)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(listLabel(q))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text(q.stem)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if q.source == "DEMO" { badge("DEMO", color: .orange) }
                                if q.isAnnulled { badge("ANULADA", color: .orange) }
                                else if q.status != "final" { badge(q.status.uppercased(), color: .secondary) }
                                if q.hasRichMedia { badge("MÍDIA", color: .blue) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Questões")
        .navigationDestination(item: $selectedQuestion) { q in
            if q.type == "discursive" { DiscursiveQuestionView(question: q) }
            else { StudyQuestionView(question: q) }
        }
        .onAppear(perform: reload)
    }

    private var areas: [String] {
        ["Todas"] + Array(Set(app.repository.allQuestions(limit: 10000).map(\.area))).filter { !$0.isEmpty }.sorted()
    }

    private func reload() {
        questions = app.repository.allQuestions(area: area == "Todas" ? nil : area)
    }

    private func listLabel(_ q: Question) -> String {
        var parts = [q.sourceEditionLabel]
        if let number = q.number { parts.append("Q\(number)") }
        return parts.joined(separator: " • ")
    }

    @ViewBuilder private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct StudyQuestionView: View {
    @EnvironmentObject var app: AppState
    let question: Question
    @State private var selected: String?
    @State private var corrected = false
    @State private var started = Date()
    @State private var confidence = "normal"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                QuestionMetadataHeader(question: question)
                Text(question.stem)
                    .font(.body)
                    .textSelection(.enabled)

                if let media = question.media, !media.isEmpty {
                    QuestionRichContentView(media: media)
                }

                VStack(spacing: 10) {
                    ForEach(question.options) { opt in
                        let correct = corrected && !question.isAnnulled && opt.label == question.correctOption
                        let wrong = corrected && !question.isAnnulled && opt.label == selected && opt.label != question.correctOption
                        let annulledSelection = corrected && question.isAnnulled && opt.label == selected
                        Button {
                            if !corrected { selected = opt.label }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(opt.label)
                                    .font(.headline)
                                    .frame(width: 30, height: 30)
                                    .background(circleColor(opt.label), in: Circle())
                                Text(opt.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.primary)
                                if corrected { outcomeIcon(opt.label) }
                            }
                            .padding()
                            .questionOptionChrome(
                                selected: !corrected && selected == opt.label,
                                correct: correct,
                                wrong: wrong,
                                annulledSelection: annulledSelection
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !corrected {
                    Picker("Confiança", selection: $confidence) {
                        Text("Sabia").tag("sure")
                        Text("Dúvida").tag("doubt")
                        Text("Chute").tag("guess")
                    }
                    .pickerStyle(.segmented)

                    Button(question.isAnnulled ? "Ver resultado" : "Corrigir") { correct() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(selected == nil || (!question.isAnnulled && question.correctOption == nil))

                    if question.correctOption == nil && !question.isAnnulled {
                        Text("Gabarito oficial ainda não disponível para esta questão.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    correction
                }
            }
            .padding()
        }
        .navigationTitle(question.number.map { "Questão \($0)" } ?? "Questão")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func correct() {
        guard let selected else { return }
        corrected = true
        app.repository.recordAnswer(
            question: question,
            selected: selected,
            seconds: Int(Date().timeIntervalSince(started)),
            confidence: confidence
        )
        app.refreshBadges()
    }

    private func circleColor(_ label: String) -> Color {
        if corrected && question.isAnnulled && label == selected { return .orange.opacity(0.22) }
        if corrected && label == question.correctOption { return .green.opacity(0.22) }
        if corrected && label == selected && label != question.correctOption { return .red.opacity(0.22) }
        if selected == label { return .accentColor.opacity(0.20) }
        return .secondary.opacity(0.12)
    }

    @ViewBuilder private func outcomeIcon(_ label: String) -> some View {
        if question.isAnnulled && label == selected {
            Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
        } else if label == question.correctOption {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if label == selected {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var correction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("Correção").font(.title2.bold())

            if question.isAnnulled {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Questão anulada pela banca", systemImage: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Sua resposta foi registrada para estudo, mas esta questão não entra na sua taxa de acertos nem no caderno de erros.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("O gabarito definitivo informa a anulação; o motivo oficial não está descrito neste banco.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            } else if let answer = question.correctOption {
                Label("Resposta correta: \(answer)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            if let text = question.explanation { Text(text) }
            if let exps = question.optionExplanations {
                ForEach(question.options) { opt in
                    if let exp = exps[opt.label] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(opt.label) — \(opt.label == question.correctOption ? "correta" : "incorreta")")
                                .font(.headline)
                            Text(exp).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let key = question.keyPoint {
                VStack(alignment: .leading, spacing: 5) {
                    Label("O que a questão queria testar", systemImage: "scope").font(.headline)
                    Text(key)
                }
                .padding()
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            Button("Adicionar à revisão") {
                app.repository.scheduleReview(questionId: question.id, reason: "manual")
            }
            .buttonStyle(.bordered)
        }
    }
}
