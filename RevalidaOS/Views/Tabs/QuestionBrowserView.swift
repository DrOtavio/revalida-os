import SwiftUI

struct QuestionBrowserView: View {
    @EnvironmentObject var app: AppState

    @State private var allQuestions: [Question] = []
    @State private var selectedQuestion: Question?
    @State private var searchText = ""
    @State private var showFilters = false

    @State private var edition = "Todas"
    @State private var area = "Todas"
    @State private var specialty = "Todas"
    @State private var topic = "Todos"
    @State private var status = "Todas"
    @State private var mediaOnly = false

    var body: some View {
        List {
            if hasActiveFilters {
                Section {
                    activeFiltersBar
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                if filteredQuestions.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhuma questão encontrada", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Ajuste os filtros ou altere a busca.")
                    } actions: {
                        Button("Limpar filtros") { resetFilters() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredQuestions) { q in
                        Button { selectedQuestion = q } label: {
                            questionRow(q)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Abrir questão")
                    }
                }
            } header: {
                HStack {
                    Text("Banco")
                    Spacer()
                    Text("\(filteredQuestions.count) de \(allQuestions.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Questões")
        .searchable(text: $searchText, prompt: "Buscar tema, especialidade ou enunciado")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: hasStructuredFilters
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .font(.title3)
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 7, y: -7)
                        }
                    }
                }
                .accessibilityLabel("Filtros")
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
        .navigationDestination(item: $selectedQuestion) { q in
            if q.type == "discursive" { DiscursiveQuestionView(question: q) }
            else { StudyQuestionView(question: q) }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private func questionRow(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(q.displayTopic)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(q.displayCategory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(listLabel(q))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Text(q.stem)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(Color.primary.opacity(0.88))

            HStack(spacing: 6) {
                if q.source == "DEMO" { badge("DEMO", color: .orange) }
                if q.isAnnulled {
                    badge("ANULADA", color: .orange)
                } else if q.status != "final" {
                    badge(q.status.uppercased(), color: .secondary)
                }
                if q.hasRichMedia {
                    badge("MÍDIA", color: .accentColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Prova") {
                    Picker("Edição", selection: $edition) {
                        ForEach(editions, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: edition) { _, _ in
                        area = "Todas"
                        specialty = "Todas"
                        topic = "Todos"
                    }

                    Picker("Situação", selection: $status) {
                        Text("Todas").tag("Todas")
                        Text("Válidas").tag("Válidas")
                        Text("Anuladas").tag("Anuladas")
                    }

                    Toggle("Somente com mídia", isOn: $mediaOnly)
                }

                Section("Classificação") {
                    Picker("Área", selection: $area) {
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: area) { _, _ in
                        specialty = "Todas"
                        topic = "Todos"
                    }

                    Picker("Especialidade", selection: $specialty) {
                        ForEach(specialties, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(specialties.count <= 1)
                    .onChange(of: specialty) { _, _ in topic = "Todos" }

                    Picker("Tema / subtema", selection: $topic) {
                        ForEach(topics, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(topics.count <= 1)
                }

                Section {
                    Button(role: .destructive) {
                        resetFilters()
                    } label: {
                        Label("Limpar todos os filtros", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!hasStructuredFilters)
                } footer: {
                    Text("Os filtros são encadeados: a edição limita as áreas; a área limita especialidades; e a especialidade limita os temas.")
                }
            }
            .navigationTitle("Filtrar questões")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { showFilters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if edition != "Todas" { filterChip(edition, icon: "calendar") }
                if area != "Todas" { filterChip(area, icon: "square.grid.2x2") }
                if specialty != "Todas" { filterChip(specialty, icon: "stethoscope") }
                if topic != "Todos" { filterChip(topic, icon: "tag") }
                if status != "Todas" { filterChip(status, icon: status == "Anuladas" ? "exclamationmark.circle" : "checkmark.circle") }
                if mediaOnly { filterChip("Com mídia", icon: "photo.on.rectangle") }
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filterChip("Busca: \(searchText)", icon: "magnifyingglass")
                }

                Button("Limpar") { resetFilters(includeSearch: true) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func filterChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
            }
    }

    private var filteredQuestions: [Question] {
        allQuestions
            .filter { q in
                if edition != "Todas", editionLabel(q) != edition { return false }
                if area != "Todas", clean(q.area) != area { return false }
                if specialty != "Todas", clean(q.specialty) != specialty { return false }
                if topic != "Todos", clean(q.topic) != topic { return false }
                if status == "Válidas", q.isAnnulled { return false }
                if status == "Anuladas", !q.isAnnulled { return false }
                if mediaOnly, !q.hasRichMedia { return false }
                if !matchesSearch(q) { return false }
                return true
            }
            .sorted(by: questionSort)
    }

    private var editions: [String] {
        ["Todas"] + Array(Set(allQuestions.map(editionLabel))).sorted(by: editionSort)
    }

    private var areas: [String] {
        ["Todas"] + uniqueValues(
            questionsMatching(edition: true, area: false, specialty: false).map { clean($0.area) }
        )
    }

    private var specialties: [String] {
        ["Todas"] + uniqueValues(
            questionsMatching(edition: true, area: true, specialty: false).compactMap { cleanOptional($0.specialty) }
        )
    }

    private var topics: [String] {
        ["Todos"] + uniqueValues(
            questionsMatching(edition: true, area: true, specialty: true).compactMap { cleanOptional($0.topic) }
        )
    }

    private func questionsMatching(edition useEdition: Bool, area useArea: Bool, specialty useSpecialty: Bool) -> [Question] {
        allQuestions.filter { q in
            if useEdition, edition != "Todas", editionLabel(q) != edition { return false }
            if useArea, area != "Todas", clean(q.area) != area { return false }
            if useSpecialty, specialty != "Todas", clean(q.specialty) != specialty { return false }
            return true
        }
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func matchesSearch(_ q: Question) -> Bool {
        let query = normalized(searchText)
        guard !query.isEmpty else { return true }

        let haystack = [
            q.stem,
            q.area,
            q.specialty ?? "",
            q.topic ?? "",
            editionLabel(q),
            q.number.map { "questao \($0) q\($0)" } ?? ""
        ].joined(separator: " ")

        return normalized(haystack).contains(query)
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func editionLabel(_ q: Question) -> String {
        if let edition = q.edition?.trimmingCharacters(in: .whitespacesAndNewlines), !edition.isEmpty {
            return edition.replacingOccurrences(of: "-", with: "/")
        }
        if let year = q.year { return String(year) }
        return "Sem edição"
    }

    private func editionSort(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Todas" { return true }
        if rhs == "Todas" { return false }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }

    private func questionSort(_ lhs: Question, _ rhs: Question) -> Bool {
        let leftYear = lhs.year ?? 0
        let rightYear = rhs.year ?? 0
        if leftYear != rightYear { return leftYear > rightYear }

        let leftEdition = editionLabel(lhs)
        let rightEdition = editionLabel(rhs)
        if leftEdition != rightEdition {
            return leftEdition.localizedStandardCompare(rightEdition) == .orderedDescending
        }
        return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
    }

    private func clean(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func cleanOptional(_ value: String?) -> String? {
        let value = clean(value)
        return value.isEmpty ? nil : value
    }

    private var hasStructuredFilters: Bool {
        edition != "Todas" ||
        area != "Todas" ||
        specialty != "Todas" ||
        topic != "Todos" ||
        status != "Todas" ||
        mediaOnly
    }

    private var hasActiveFilters: Bool {
        hasStructuredFilters || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeFilterCount: Int {
        [
            edition != "Todas",
            area != "Todas",
            specialty != "Todas",
            topic != "Todos",
            status != "Todas",
            mediaOnly
        ].filter { $0 }.count
    }

    private func resetFilters(includeSearch: Bool = false) {
        edition = "Todas"
        area = "Todas"
        specialty = "Todas"
        topic = "Todos"
        status = "Todas"
        mediaOnly = false
        if includeSearch { searchText = "" }
    }

    private func reload() {
        allQuestions = app.repository.allQuestions(limit: 10000)
    }

    private func listLabel(_ q: Question) -> String {
        var parts = [editionLabel(q)]
        if let number = q.number { parts.append("Q\(number)") }
        return parts.joined(separator: " • ")
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.16), lineWidth: 0.5)
            }
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
