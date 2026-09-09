import SwiftUI

struct SimulationsView: View {
    @EnvironmentObject var app: AppState
    @State private var runner: SimulationSetup?
    @State private var message: String?

    var body: some View {
        List {
            Section("Simulado completo") {
                Button { createRandom(100, mode: "real") } label: { simulationRow("Aleatório balanceado — 100", "5 horas • resultado no final", "shuffle") }
                    .buttonStyle(.plain)
                Button { createRandom(100, mode: "flex") } label: { simulationRow("Aleatório flexível — 100", "5 horas • cronômetro pausável", "pause.circle") }
                    .buttonStyle(.plain)
            }
            Section("Provas oficiais") {
                ForEach(app.repository.allExams()) { exam in
                    let count = app.repository.questionCount(examId: exam.id)
                    Button { startExam(exam) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(exam.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("\(exam.durationMinutes / 60)h • corte \(exam.officialCutoff.map(String.init) ?? "a definir") • \(count)/\(exam.objectiveQuestions) importadas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                }
            }
            Section("Treino rápido") {
                Button { createRandom(10, mode: "flex") } label: { simulationRow("Mini simulado — 10", "para testar fluxo", "bolt.fill") }
                    .buttonStyle(.plain)
                Button { createRandom(20, mode: "flex") } label: { simulationRow("Mini simulado — 20", "treino curto", "bolt") }
                    .buttonStyle(.plain)
            }
            Section("Histórico") {
                ForEach(app.repository.latestSimulations(limit: 10)) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.title)
                            Text(s.finishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(s.score)/\(s.total)").font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle("Simulados")
        .navigationDestination(item: $runner) { setup in SimulationRunnerView(setup: setup) }
        .alert("Simulado", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    @ViewBuilder private func simulationRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func createRandom(_ count: Int, mode: String) {
        let qs = app.repository.randomBalancedQuestions(count: count)
        guard qs.count == count else {
            message = "O banco atual possui somente \(qs.count) questões disponíveis para esse sorteio. Importe os packs oficiais para liberar o simulado completo."
            return
        }
        runner = SimulationSetup(
            id: UUID().uuidString,
            title: "Aleatório balanceado",
            questions: qs,
            durationMinutes: count == 100 ? 300 : max(30, count * 3),
            cutoff: count == 100 ? AppConfig.safetyTarget : nil,
            mode: mode
        )
    }

    private func startExam(_ exam: Exam) {
        let qs = app.repository.questionsForExam(exam.id)
        guard !qs.isEmpty else { return }
        runner = SimulationSetup(
            id: UUID().uuidString,
            title: exam.name,
            questions: qs,
            durationMinutes: exam.durationMinutes,
            cutoff: exam.officialCutoff,
            mode: "real"
        )
    }
}

struct SimulationSetup: Identifiable, Hashable {
    let id: String
    let title: String
    let questions: [Question]
    let durationMinutes: Int
    let cutoff: Int?
    let mode: String
}

struct SimulationRunnerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    let setup: SimulationSetup

    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var flags: Set<String> = []
    @State private var started = Date()
    @State private var remaining = 0
    @State private var deadline: Date?
    @State private var finished = false
    @State private var showMap = false
    @State private var showFinish = false
    @State private var isPaused = false

    private var totalSeconds: Int { setup.durationMinutes * 60 }

    var body: some View {
        Group { finished ? AnyView(resultView) : AnyView(examView) }
            .navigationBarBackButtonHidden(!finished)
            .onAppear {
                initializeTimerIfNeeded()
                syncRemainingWithClock()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { syncRemainingWithClock() }
            }
            .task { await timerLoop() }
            .confirmationDialog("Finalizar simulado?", isPresented: $showFinish, titleVisibility: .visible) {
                Button("Finalizar e corrigir", role: .destructive) { finish() }
                Button("Continuar", role: .cancel) {}
            }
            .sheet(isPresented: $showMap) {
                QuestionMapView(questions: setup.questions, current: $index, answers: answers, flags: flags)
            }
    }

    private var examView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(index + 1)/\(setup.questions.count)").font(.headline)
                Spacer()
                if setup.mode == "flex" {
                    Button { togglePause() } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(isPaused ? "Continuar cronômetro" : "Pausar cronômetro")
                }
                Label(timeString(remaining), systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remaining < 900 ? Color.orange : Color.primary)
                Button { showMap = true } label: { Image(systemName: "square.grid.3x3.fill") }
            }
            .padding()
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QuestionMetadataHeader(question: current)
                    Text(current.stem)
                        .textSelection(.enabled)

                    if let media = current.media, !media.isEmpty {
                        QuestionRichContentView(media: media)
                    }

                    ForEach(current.options) { opt in
                        let selected = answers[current.id] == opt.label
                        Button { answers[current.id] = opt.label } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(opt.label)
                                    .font(.headline)
                                    .frame(width: 30, height: 30)
                                    .background(selected ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.10), in: Circle())
                                Text(opt.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.primary)
                            }
                            .padding()
                            .questionOptionChrome(selected: selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }

            HStack {
                Button {
                    if flags.contains(current.id) { flags.remove(current.id) }
                    else { flags.insert(current.id) }
                } label: {
                    Image(systemName: flags.contains(current.id) ? "flag.fill" : "flag")
                    Text("Revisar")
                }
                .buttonStyle(.bordered)

                Spacer()
                Button("Anterior") { index = max(0, index - 1) }.disabled(index == 0)
                if index < setup.questions.count - 1 {
                    Button("Próxima") { index += 1 }.buttonStyle(.borderedProminent)
                } else {
                    Button("Finalizar") { showFinish = true }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(setup.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Finalizar") { showFinish = true } }
        }
    }

    private var resultView: some View {
        let validQuestions = setup.questions.filter { !$0.isAnnulled && $0.correctOption != nil }
        let annulledCount = setup.questions.filter(\.isAnnulled).count
        let validScore = validQuestions.filter { answers[$0.id] == $0.correctOption }.count
        let comparableScore = validScore + annulledCount

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Resultado").font(.largeTitle.bold())
                HStack(alignment: .lastTextBaseline) {
                    Text("\(validScore)").font(.system(size: 60, weight: .bold, design: .rounded))
                    Text("/ \(validQuestions.count) válidas").font(.title2).foregroundStyle(.secondary)
                }
                if annulledCount > 0 {
                    Label("\(annulledCount) questão\(annulledCount == 1 ? "" : "ões") anulada\(annulledCount == 1 ? "" : "s")", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }

                if let cutoff = setup.cutoff {
                    let margin = comparableScore - cutoff
                    Label(
                        comparableScore >= cutoff ? "Acima do corte/referência" : "Abaixo do corte/referência",
                        systemImage: comparableScore >= cutoff ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(comparableScore >= cutoff ? .green : .orange)
                    Text("Pontuação comparável: \(comparableScore)/\(setup.questions.count) • referência: \(cutoff) • margem \(margin >= 0 ? "+" : "")\(margin)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    MetricCard(title: "Tempo", value: timeString(activeElapsedSeconds), subtitle: "utilizado", systemImage: "clock")
                    MetricCard(title: "Respondidas", value: "\(answers.count)", subtitle: "de \(setup.questions.count)", systemImage: "checkmark.circle")
                }

                Text("Revisão das questões").font(.title2.bold())
                ForEach(Array(setup.questions.enumerated()), id: \.element.id) { i, q in
                    NavigationLink {
                        SimulationQuestionResultView(question: q, selected: answers[q.id])
                    } label: {
                        HStack {
                            Text("Q\(i + 1)")
                            Text(q.displayTopic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            if q.isAnnulled {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
                            } else if let c = q.correctOption {
                                Image(systemName: answers[q.id] == c ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(answers[q.id] == c ? .green : .red)
                            } else {
                                Image(systemName: "minus.circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(setup.title)
        .navigationBarBackButtonHidden(false)
    }

    private var current: Question { setup.questions[index] }
    private var activeElapsedSeconds: Int { max(0, totalSeconds - remaining) }

    private func initializeTimerIfNeeded() {
        guard !finished else { return }
        if remaining == 0 && deadline == nil {
            remaining = totalSeconds
            deadline = Date().addingTimeInterval(TimeInterval(totalSeconds))
        }
    }

    private func syncRemainingWithClock() {
        guard !finished, !isPaused, let deadline else { return }
        let newValue = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        remaining = newValue
        if newValue == 0 { finish() }
    }

    private func togglePause() {
        guard setup.mode == "flex", !finished else { return }
        if isPaused {
            isPaused = false
            deadline = Date().addingTimeInterval(TimeInterval(remaining))
        } else {
            syncRemainingWithClock()
            isPaused = true
            deadline = nil
        }
    }

    private func timerLoop() async {
        while !Task.isCancelled && !finished {
            if !isPaused { syncRemainingWithClock() }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        syncRemainingWithClockWithoutFinishing()
        finished = true
        let end = Date()
        let annulledCount = setup.questions.filter(\.isAnnulled).count
        let validScore = setup.questions.filter { !$0.isAnnulled && $0.correctOption != nil && answers[$0.id] == $0.correctOption }.count
        let comparableScore = validScore + annulledCount
        app.repository.saveSimulation(
            id: setup.id,
            title: setup.title,
            startedAt: started,
            finishedAt: end,
            score: comparableScore,
            total: setup.questions.count,
            cutoff: setup.cutoff,
            durationSeconds: activeElapsedSeconds,
            mode: setup.mode,
            questionIds: setup.questions.map(\.id),
            answers: answers,
            flags: flags
        )
        for q in setup.questions {
            if let selected = answers[q.id] {
                app.repository.recordAnswer(question: q, selected: selected, seconds: 0, confidence: "simulation")
            }
        }
        app.refreshBadges()
    }

    private func syncRemainingWithClockWithoutFinishing() {
        guard !isPaused, let deadline else { return }
        remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

struct QuestionMapView: View {
    let questions: [Question]
    @Binding var current: Int
    let answers: [String: String]
    let flags: Set<String>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(Array(questions.enumerated()), id: \.element.id) { i, q in
                        Button {
                            current = i
                            dismiss()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(i == current ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                                    .frame(height: 48)
                                Text("\(i + 1)").font(.headline)
                                VStack {
                                    HStack { Spacer(); if flags.contains(q.id) { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange) } }
                                    Spacer()
                                    HStack { Spacer(); if answers[q.id] != nil { Circle().fill(Color.green).frame(width: 7, height: 7) } }
                                }
                                .padding(5)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Mapa da prova")
        }
    }
}

struct SimulationQuestionResultView: View {
    let question: Question
    let selected: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuestionMetadataHeader(question: question)
                Text(question.stem)
                    .textSelection(.enabled)

                if let media = question.media, !media.isEmpty {
                    QuestionRichContentView(media: media)
                }

                if question.isAnnulled {
                    Label("Questão anulada — não contabilizada como erro", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }

                ForEach(question.options) { opt in
                    let correct = !question.isAnnulled && opt.label == question.correctOption
                    let wrong = !question.isAnnulled && opt.label == selected && opt.label != question.correctOption
                    let annulledSelection = question.isAnnulled && opt.label == selected
                    HStack(alignment: .top) {
                        Text(opt.label).bold()
                        Text(opt.text)
                        Spacer()
                        if correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                        else if annulledSelection { Image(systemName: "minus.circle.fill").foregroundStyle(.orange) }
                    }
                    .padding()
                    .questionOptionChrome(correct: correct, wrong: wrong, annulledSelection: annulledSelection)
                }

                if let e = question.explanation {
                    Divider()
                    Text("Comentário").font(.headline)
                    Text(e)
                }

                if let ex = question.optionExplanations {
                    ForEach(question.options) { opt in
                        if let t = ex[opt.label] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(opt.label) — \(opt.label == question.correctOption ? "correta" : "incorreta")")
                                    .font(.headline)
                                Text(t)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let k = question.keyPoint {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("O que a questão queria testar", systemImage: "scope")
                            .font(.headline)
                        Text(k)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Correção")
    }
}
