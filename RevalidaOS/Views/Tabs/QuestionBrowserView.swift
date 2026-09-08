import SwiftUI

struct QuestionBrowserView: View {
    @EnvironmentObject var app: AppState
    @State private var area = "Todas"
    @State private var questions: [Question] = []
    @State private var selectedQuestion: Question?

    var body: some View {
        List {
            Section {
                Picker("Área", selection:$area) { ForEach(areas, id:\.self) { Text($0).tag($0) } }
                    .onChange(of: area) { _, _ in reload() }
            }
            Section("Banco — \(questions.count) questões") {
                ForEach(questions) { q in
                    Button { selectedQuestion=q } label: {
                        VStack(alignment:.leading,spacing:5) {
                            HStack { Text(q.area).font(.caption.bold()).foregroundStyle(.tint); Spacer(); Text(label(q)).font(.caption).foregroundStyle(.secondary) }
                            Text(q.stem).lineLimit(3).foregroundStyle(.primary)
                            HStack { if q.source == "DEMO" { Text("DEMO").font(.caption2.bold()).padding(.horizontal,6).padding(.vertical,2).background(.orange.opacity(0.15),in:Capsule()) }; if q.status != "final" { Text(q.status.uppercased()).font(.caption2).foregroundStyle(.secondary) } }
                        }.padding(.vertical,4)
                    }
                }
            }
        }
        .navigationTitle("Questões")
        .navigationDestination(item:$selectedQuestion) { q in
            if q.type == "discursive" { DiscursiveQuestionView(question: q) } else { StudyQuestionView(question: q) }
        }
        .onAppear(perform: reload)
    }

    private var areas:[String] { ["Todas"] + Array(Set(app.repository.allQuestions(limit:10000).map(\.area))).sorted() }
    private func reload(){ questions=app.repository.allQuestions(area: area=="Todas" ? nil:area) }
    private func label(_ q: Question) -> String {
        var parts = [q.source]
        if let year = q.year { parts.append(String(year)) }
        if let number = q.number { parts.append("Q\(number)") }
        return parts.joined(separator: " • ")
    }
}

struct StudyQuestionView: View {
    @EnvironmentObject var app: AppState
    let question: Question
    @State private var selected: String?
    @State private var corrected=false
    @State private var started=Date()
    @State private var confidence="normal"

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { Text(question.area).font(.subheadline.bold()).foregroundStyle(.tint); Spacer(); Text(question.source).font(.caption).foregroundStyle(.secondary) }
                Text(question.stem).font(.body).textSelection(.enabled)
                VStack(spacing:10) {
                    ForEach(question.options) { opt in
                        Button { if !corrected { selected=opt.label } } label: {
                            HStack(alignment:.top,spacing:12) {
                                Text(opt.label).font(.headline).frame(width:30,height:30).background(optionBackground(opt.label),in:Circle())
                                Text(opt.text).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.primary)
                                if corrected { outcomeIcon(opt.label) }
                            }.padding().background(selected==opt.label ? Color.accentColor.opacity(0.08):Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain)
                    }
                }
                if !corrected {
                    Picker("Confiança",selection:$confidence){ Text("Sabia").tag("sure");Text("Dúvida").tag("doubt");Text("Chute").tag("guess") }.pickerStyle(.segmented)
                    Button("Corrigir") { correct() }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity).disabled(selected==nil || question.correctOption==nil)
                    if question.correctOption == nil { Text("Gabarito oficial ainda não disponível para esta questão.").font(.footnote).foregroundStyle(.secondary) }
                } else { correction }
            }.padding()
        }.navigationTitle(question.number.map{"Questão \($0)"} ?? "Questão").navigationBarTitleDisplayMode(.inline)
    }

    private func correct(){ guard let selected else{return}; corrected=true; app.repository.recordAnswer(question:question,selected:selected,seconds:Int(Date().timeIntervalSince(started)),confidence:confidence); app.refreshBadges() }
    private func optionBackground(_ label:String)->Color { if corrected, label==question.correctOption { return .green.opacity(0.2) }; if corrected, label==selected, label != question.correctOption { return .red.opacity(0.2) }; return .secondary.opacity(0.12) }
    @ViewBuilder private func outcomeIcon(_ label:String)->some View { if label==question.correctOption { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) } else if label==selected { Image(systemName:"xmark.circle.fill").foregroundStyle(.red) } }
    private var correction: some View {
        VStack(alignment:.leading,spacing:14) {
            Divider(); Text("Correção").font(.title2.bold())
            if let answer=question.correctOption { Label("Resposta correta: \(answer)",systemImage:"checkmark.seal.fill").foregroundStyle(.green) }
            if let text=question.explanation { Text(text) }
            if let exps=question.optionExplanations {
                ForEach(question.options) { opt in if let exp=exps[opt.label] { VStack(alignment:.leading,spacing:4){Text("\(opt.label) — \(opt.label==question.correctOption ? "correta" : "incorreta")").font(.headline);Text(exp).foregroundStyle(.secondary)} } }
            }
            if let key=question.keyPoint { VStack(alignment:.leading,spacing:5){Label("O que a questão queria testar",systemImage:"scope").font(.headline);Text(key)}.padding().background(Color.accentColor.opacity(0.1),in:RoundedRectangle(cornerRadius:14)) }
            Button("Adicionar à revisão") { app.repository.scheduleReview(questionId:question.id,reason:"manual") }.buttonStyle(.bordered)
        }
    }
}
