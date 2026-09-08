import SwiftUI

struct SimulationsView: View {
    @EnvironmentObject var app: AppState
    @State private var runner: SimulationSetup?
    @State private var message: String?

    var body: some View {
        List {
            Section("Simulado completo") {
                Button { createRandom(100, mode:"real") } label: { simulationRow("Aleatório balanceado — 100", "5 horas • resultado no final", "shuffle") }
                Button { createRandom(100, mode:"flex") } label: { simulationRow("Aleatório flexível — 100", "5 horas • cronômetro pausável", "pause.circle") }
            }
            Section("Provas oficiais") {
                ForEach(app.repository.allExams()) { exam in
                    let count=app.repository.questionCount(examId:exam.id)
                    Button { startExam(exam) } label: {
                        HStack { VStack(alignment:.leading){Text(exam.name).foregroundStyle(.primary);Text("\(exam.durationMinutes/60)h • corte \(exam.officialCutoff.map(String.init) ?? "a definir") • \(count)/\(exam.objectiveQuestions) importadas").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right") }
                    }.disabled(count == 0)
                }
            }
            Section("Treino rápido") {
                Button { createRandom(10, mode:"flex") } label: { simulationRow("Mini simulado — 10", "para testar fluxo", "bolt.fill") }
                Button { createRandom(20, mode:"flex") } label: { simulationRow("Mini simulado — 20", "treino curto", "bolt") }
            }
            Section("Histórico") {
                ForEach(app.repository.latestSimulations(limit:10)) { s in
                    HStack { VStack(alignment:.leading){Text(s.title);Text(s.finishedAt?.formatted(date:.abbreviated,time:.shortened) ?? "").font(.caption).foregroundStyle(.secondary)};Spacer();Text("\(s.score)/\(s.total)").font(.headline.monospacedDigit()) }
                }
            }
        }
        .navigationTitle("Simulados")
        .navigationDestination(item:$runner) { setup in SimulationRunnerView(setup:setup) }
        .alert("Simulado", isPresented:Binding(get:{message != nil},set:{if !$0{message=nil}})){Button("OK",role:.cancel){}} message:{Text(message ?? "")}
    }

    @ViewBuilder private func simulationRow(_ title:String,_ subtitle:String,_ icon:String)->some View { HStack{Image(systemName:icon).frame(width:28).foregroundStyle(.tint);VStack(alignment:.leading){Text(title).foregroundStyle(.primary);Text(subtitle).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right")} }
    private func createRandom(_ count:Int,mode:String){ let qs=app.repository.randomBalancedQuestions(count:count); guard qs.count==count else{message="O banco atual possui somente \(qs.count) questões disponíveis para esse sorteio. Importe os packs oficiais para liberar o simulado completo.";return}; runner=SimulationSetup(id:UUID().uuidString,title:"Aleatório balanceado",questions:qs,durationMinutes:count==100 ? 300:max(30,count*3),cutoff:count==100 ? AppConfig.safetyTarget:nil,mode:mode) }
    private func startExam(_ exam:Exam){ let qs=app.repository.questionsForExam(exam.id); guard !qs.isEmpty else{return}; runner=SimulationSetup(id:UUID().uuidString,title:exam.name,questions:qs,durationMinutes:exam.durationMinutes,cutoff:exam.officialCutoff,mode:"real") }
}

struct SimulationSetup: Identifiable, Hashable { let id:String;let title:String;let questions:[Question];let durationMinutes:Int;let cutoff:Int?;let mode:String }

struct SimulationRunnerView: View {
    @EnvironmentObject var app: AppState
    let setup: SimulationSetup
    @State private var index=0
    @State private var answers:[String:String]=[:]
    @State private var flags:Set<String>=[]
    @State private var started=Date()
    @State private var remaining=0
    @State private var finished=false
    @State private var showMap=false
    @State private var showFinish=false
    @State private var isPaused=false

    var body: some View {
        Group { if finished { resultView } else { examView } }
            .navigationBarBackButtonHidden(!finished)
            .onAppear { if remaining==0 { remaining=setup.durationMinutes*60 } }
            .task { await timerLoop() }
            .confirmationDialog("Finalizar simulado?",isPresented:$showFinish,titleVisibility:.visible){Button("Finalizar e corrigir",role:.destructive){finish()};Button("Continuar",role:.cancel){}}
            .sheet(isPresented:$showMap){QuestionMapView(questions:setup.questions,current:$index,answers:answers,flags:flags)}
    }

    private var examView: some View {
        VStack(spacing:0){
            HStack{
                Text("\(index+1)/\(setup.questions.count)").font(.headline)
                Spacer()
                if setup.mode == "flex" {
                    Button { isPaused.toggle() } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityLabel(isPaused ? "Continuar cronômetro" : "Pausar cronômetro")
                }
                Label(timeString(remaining),systemImage:"timer")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remaining < 900 ? Color.orange : Color.primary)
                Button{showMap=true}label:{Image(systemName:"square.grid.3x3.fill")}
            }.padding().background(.bar)
            ScrollView{VStack(alignment:.leading,spacing:16){Text(current.area).font(.caption.bold()).foregroundStyle(.tint);Text(current.stem);ForEach(current.options){opt in Button{answers[current.id]=opt.label}label:{HStack(alignment:.top,spacing:10){Text(opt.label).font(.headline).frame(width:30,height:30).background(answers[current.id]==opt.label ? Color.accentColor.opacity(0.2):Color.secondary.opacity(0.1),in:Circle());Text(opt.text).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.primary)}.padding().background(answers[current.id]==opt.label ? Color.accentColor.opacity(0.07):Color.secondary.opacity(0.04),in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain)}}.padding()}
            HStack{Button{ if flags.contains(current.id) { flags.remove(current.id) } else { flags.insert(current.id) } }label:{Image(systemName:flags.contains(current.id) ? "flag.fill":"flag");Text("Revisar")}.buttonStyle(.bordered);Spacer();Button("Anterior"){index=max(0,index-1)}.disabled(index==0);if index<setup.questions.count-1{Button("Próxima"){index+=1}.buttonStyle(.borderedProminent)}else{Button("Finalizar"){showFinish=true}.buttonStyle(.borderedProminent)}}.padding().background(.bar)
        }.navigationTitle(setup.title).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("Finalizar"){showFinish=true}}}
    }

    private var resultView: some View {
        let score=setup.questions.filter{$0.correctOption != nil && answers[$0.id]==$0.correctOption}.count
        return ScrollView{VStack(alignment:.leading,spacing:20){
            Text("Resultado").font(.largeTitle.bold())
            HStack(alignment:.lastTextBaseline){Text("\(score)").font(.system(size:60,weight:.bold,design:.rounded));Text("/ \(setup.questions.count)").font(.title2).foregroundStyle(.secondary)}
            if let cutoff=setup.cutoff{let margin=score-cutoff;Label(score>=cutoff ? "Acima do corte/referência" : "Abaixo do corte/referência",systemImage:score>=cutoff ? "checkmark.seal.fill":"exclamationmark.triangle.fill").font(.headline).foregroundStyle(score>=cutoff ? .green:.orange);Text("Referência: \(cutoff) • margem \(margin>=0 ? "+":"")\(margin)").foregroundStyle(.secondary)}
            HStack{MetricCard(title:"Tempo",value:timeString(Int(Date().timeIntervalSince(started))),subtitle:"utilizado",systemImage:"clock");MetricCard(title:"Respondidas",value:"\(answers.count)",subtitle:"de \(setup.questions.count)",systemImage:"checkmark.circle")}
            Text("Revisão das questões").font(.title2.bold())
            ForEach(Array(setup.questions.enumerated()),id:\.element.id){i,q in NavigationLink{SimulationQuestionResultView(question:q,selected:answers[q.id])}label:{HStack{Text("Q\(i+1)");Spacer();if let c=q.correctOption{Image(systemName:answers[q.id]==c ? "checkmark.circle.fill":"xmark.circle.fill").foregroundStyle(answers[q.id]==c ? .green:.red)}else{Image(systemName:"minus.circle").foregroundStyle(.secondary)}}}}
        }.padding()}.navigationTitle(setup.title).navigationBarBackButtonHidden(false)
    }

    private var current:Question{setup.questions[index]}
    private func timerLoop() async {
        while !finished && remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !finished else { break }
            if setup.mode == "flex" && isPaused { continue }
            remaining = max(0, remaining - 1)
            if remaining == 0 { finish() }
        }
    }
    private func finish(){ guard !finished else{return}; finished=true; let end=Date();let score=setup.questions.filter{$0.correctOption != nil && answers[$0.id]==$0.correctOption}.count;app.repository.saveSimulation(id:setup.id,title:setup.title,startedAt:started,finishedAt:end,score:score,total:setup.questions.count,cutoff:setup.cutoff,durationSeconds:Int(end.timeIntervalSince(started)),mode:setup.mode,questionIds:setup.questions.map(\.id),answers:answers,flags:flags);for q in setup.questions{if let selected=answers[q.id]{app.repository.recordAnswer(question:q,selected:selected,seconds:0,confidence:"simulation")}};app.refreshBadges() }
    private func timeString(_ seconds:Int)->String{String(format:"%02d:%02d:%02d",seconds/3600,(seconds%3600)/60,seconds%60)}
}

struct QuestionMapView: View { let questions:[Question];@Binding var current:Int;let answers:[String:String];let flags:Set<String>;@Environment(\.dismiss)var dismiss;var body:some View{NavigationStack{ScrollView{LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:5),spacing:12){ForEach(Array(questions.enumerated()),id:\.element.id){i,q in Button{current=i;dismiss()}label:{ZStack{RoundedRectangle(cornerRadius:10).fill(i==current ? Color.accentColor.opacity(0.2):Color.secondary.opacity(0.08)).frame(height:48);Text("\(i+1)").font(.headline);VStack{HStack{Spacer();if flags.contains(q.id){Image(systemName:"flag.fill").font(.caption).foregroundStyle(.orange)}};Spacer();HStack{Spacer();if answers[q.id] != nil{Circle().fill(Color.green).frame(width:7,height:7)}}}.padding(5)}}}}.padding()}.navigationTitle("Mapa da prova")}}}

struct SimulationQuestionResultView: View {let question:Question;let selected:String?;var body:some View{ScrollView{VStack(alignment:.leading,spacing:14){Text(question.stem);ForEach(question.options){opt in HStack(alignment:.top){Text(opt.label).bold();Text(opt.text);Spacer();if opt.label==question.correctOption{Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}else if opt.label==selected{Image(systemName:"xmark.circle.fill").foregroundStyle(.red)}}.padding().background(Color.secondary.opacity(0.05),in:RoundedRectangle(cornerRadius:12))};if let e=question.explanation{Divider();Text("Comentário").font(.headline);Text(e)};if let ex=question.optionExplanations{ForEach(question.options){opt in if let t=ex[opt.label]{Text("\(opt.label): \(t)").font(.subheadline).foregroundStyle(.secondary)}}};if let k=question.keyPoint{Text(k).padding().background(Color.accentColor.opacity(0.1),in:RoundedRectangle(cornerRadius:12))}}.padding()}.navigationTitle("Correção")}}
