import Foundation

final class AppRepository {
    private let store: SQLiteStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: SQLiteStore) { self.store = store }

    func prepareDatabase() throws {
        try store.execute("""
        CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS exams (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, year INTEGER NOT NULL, edition TEXT NOT NULL, board TEXT NOT NULL,
          format_version TEXT NOT NULL, objective_questions INTEGER NOT NULL, discursive_questions INTEGER NOT NULL,
          duration_minutes INTEGER NOT NULL, official_cutoff INTEGER, exam_date TEXT, source_url TEXT
        );
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS questions (
          id TEXT PRIMARY KEY, exam_id TEXT, number INTEGER, source TEXT NOT NULL, year INTEGER, edition TEXT, type TEXT NOT NULL,
          area TEXT NOT NULL, specialty TEXT, topic TEXT, stem TEXT NOT NULL, options_json TEXT NOT NULL,
          correct_option TEXT, explanation TEXT, option_explanations_json TEXT, key_point TEXT, status TEXT NOT NULL,
          official_source_url TEXT
        );
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS news (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, category TEXT NOT NULL, priority TEXT NOT NULL,
          published_at TEXT NOT NULL, event_date TEXT, end_date TEXT, source_url TEXT, is_read INTEGER NOT NULL DEFAULT 0
        );
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS user_answers (
          id INTEGER PRIMARY KEY AUTOINCREMENT, question_id TEXT NOT NULL, selected_option TEXT NOT NULL,
          is_correct INTEGER NOT NULL, answered_at REAL NOT NULL, response_seconds INTEGER NOT NULL DEFAULT 0,
          confidence TEXT NOT NULL DEFAULT 'normal'
        );
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS reviews (
          question_id TEXT PRIMARY KEY, due_at REAL NOT NULL, reason TEXT NOT NULL, interval_days INTEGER NOT NULL DEFAULT 1
        );
        """)
        try store.execute("""
        CREATE TABLE IF NOT EXISTS simulations (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, started_at REAL NOT NULL, finished_at REAL, score INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL, cutoff INTEGER, duration_seconds INTEGER NOT NULL DEFAULT 0, mode TEXT NOT NULL,
          question_ids_json TEXT NOT NULL, answers_json TEXT NOT NULL DEFAULT '{}', flags_json TEXT NOT NULL DEFAULT '[]'
        );
        """)
    }

    func importBundledSeedIfNeeded() throws {
        guard contentVersion() == 0 else { return }
        guard let url = Bundle.main.url(forResource: "seed_pack", withExtension: "json") else { return }
        let data = try Data(contentsOf: url)
        try importPack(data: data)
    }

    func importPack(data: Data) throws {
        let pack = try decoder.decode(ContentPack.self, from: data)
        try store.transaction {
            for exam in pack.exams { try upsert(exam) }
            for question in pack.questions { try upsert(question) }
            for news in pack.news { try upsert(news) }
            try setMetadata(key: "content_version", value: String(pack.version))
            try setMetadata(key: "content_generated_at", value: pack.generatedAt)
        }
    }

    func contentVersion() -> Int {
        (try? store.query("SELECT value FROM metadata WHERE key='content_version' LIMIT 1;").first?["value"]?.string.flatMap(Int.init)) ?? 0
    }

    func allExams() -> [Exam] {
        let rows = (try? store.query("SELECT * FROM exams ORDER BY year DESC, edition DESC;")) ?? []
        return rows.compactMap(decodeExam)
    }

    func questionCount(examId: String? = nil) -> Int {
        let rows: [[String: SQLiteValue]]
        if let examId {
            rows = (try? store.query(
                "SELECT COUNT(*) c FROM questions WHERE exam_id=? AND type='objective';",
                bindings: [.text(examId)]
            )) ?? []
        } else {
            rows = (try? store.query("SELECT COUNT(*) c FROM questions;")) ?? []
        }
        return Int(rows.first?["c"]?.int ?? 0)
    }

    func allQuestions(area: String? = nil, source: String? = nil, limit: Int = 5000) -> [Question] {
        var sql = "SELECT * FROM questions WHERE 1=1"
        var bind: [SQLiteValue] = []
        if let area, !area.isEmpty { sql += " AND area=?"; bind.append(.text(area)) }
        if let source, !source.isEmpty { sql += " AND source=?"; bind.append(.text(source)) }
        sql += " ORDER BY COALESCE(year,0) DESC, COALESCE(number,0) ASC LIMIT ?;"; bind.append(.int(Int64(limit)))
        return ((try? store.query(sql, bindings: bind)) ?? []).compactMap(decodeQuestion)
    }

    func questions(ids: [String]) -> [Question] {
        guard !ids.isEmpty else { return [] }
        return ids.compactMap { id in
            ((try? store.query("SELECT * FROM questions WHERE id=? LIMIT 1;", bindings: [.text(id)])) ?? []).first.flatMap(decodeQuestion)
        }
    }

    func questionsForExam(_ examId: String) -> [Question] {
        ((try? store.query(
            "SELECT * FROM questions WHERE exam_id=? AND type='objective' ORDER BY number ASC;",
            bindings: [.text(examId)]
        )) ?? []).compactMap(decodeQuestion)
    }

    func randomBalancedQuestions(count: Int) -> [Question] {
        guard count > 0 else { return [] }

        // Prefer official, answered objective items. DEMO items are only a fallback
        // while the official historical packs have not been imported yet.
        let officialRows = (try? store.query(
            "SELECT * FROM questions WHERE type='objective' AND correct_option IS NOT NULL AND source='INEP' ORDER BY COALESCE(year,0) DESC, COALESCE(number,0) ASC;"
        )) ?? []
        let official = officialRows.compactMap(decodeQuestion)
        let allEligibleRows = (try? store.query(
            "SELECT * FROM questions WHERE type='objective' AND correct_option IS NOT NULL ORDER BY COALESCE(year,0) DESC, COALESCE(number,0) ASC;"
        )) ?? []
        let allEligible = allEligibleRows.compactMap(decodeQuestion)
        let pool = official.count >= count ? official : allEligible
        guard !pool.isEmpty else { return [] }

        let grouped = Dictionary(grouping: pool, by: \Question.area)
        let distribution = currentAreaDistribution()
        var chosen: [Question] = []
        var used = Set<String>()

        for dist in distribution {
            let target = Int((Double(count) * dist.weight).rounded())
            let areaPool = (grouped[dist.area] ?? []).shuffled()
            for question in areaPool.prefix(target) where !used.contains(question.id) {
                chosen.append(question)
                used.insert(question.id)
            }
        }

        // Rounding or an area with too few questions can leave vacancies. Fill them
        // from the eligible pool without duplicates.
        if chosen.count < count {
            for question in pool.shuffled() where !used.contains(question.id) {
                chosen.append(question)
                used.insert(question.id)
                if chosen.count == count { break }
            }
        }

        return Array(chosen.prefix(count)).shuffled()
    }

    /// Matrix for the random full simulation. Uses up to the three most recent
    /// complete official objective exams. If those are not available yet, falls
    /// back to all official objective items, then to the local demo content.
    private func currentAreaDistribution() -> [(area: String, weight: Double)] {
        let completeExamRows = (try? store.query("""
        SELECT e.id
        FROM exams e
        WHERE e.objective_questions > 0
          AND (SELECT COUNT(*) FROM questions q
               WHERE q.exam_id=e.id AND q.type='objective'
                 AND q.correct_option IS NOT NULL AND q.source='INEP') >= e.objective_questions
        ORDER BY e.year DESC, e.edition DESC
        LIMIT 3;
        """)) ?? []
        let examIds = completeExamRows.compactMap { $0["id"]?.string }

        var rows: [[String: SQLiteValue]] = []
        if !examIds.isEmpty {
            let placeholders = Array(repeating: "?", count: examIds.count).joined(separator: ",")
            rows = (try? store.query(
                "SELECT area, COUNT(*) c FROM questions WHERE type='objective' AND correct_option IS NOT NULL AND source='INEP' AND exam_id IN (\(placeholders)) GROUP BY area ORDER BY c DESC;",
                bindings: examIds.map(SQLiteValue.text)
            )) ?? []
        }

        if rows.isEmpty {
            rows = (try? store.query(
                "SELECT area, COUNT(*) c FROM questions WHERE type='objective' AND correct_option IS NOT NULL AND source='INEP' GROUP BY area ORDER BY c DESC;"
            )) ?? []
        }
        if rows.isEmpty {
            rows = (try? store.query(
                "SELECT area, COUNT(*) c FROM questions WHERE type='objective' AND correct_option IS NOT NULL GROUP BY area ORDER BY c DESC;"
            )) ?? []
        }

        let total = rows.reduce(0) { $0 + Int($1["c"]?.int ?? 0) }
        guard total > 0 else { return [] }
        return rows.compactMap { row in
            guard let area = row["area"]?.string else { return nil }
            return (area, Double(row["c"]?.int ?? 0) / Double(total))
        }
    }

    func recordAnswer(question: Question, selected: String, seconds: Int, confidence: String) {
        let correct = question.correctOption.map { $0 == selected } ?? false
        try? store.execute("INSERT INTO user_answers(question_id,selected_option,is_correct,answered_at,response_seconds,confidence) VALUES(?,?,?,?,?,?);",
                           bindings: [.text(question.id), .text(selected), .int(correct ? 1 : 0), .double(Date().timeIntervalSince1970), .int(Int64(seconds)), .text(confidence)])
        if !correct || confidence == "doubt" || confidence == "guess" {
            scheduleReview(questionId: question.id, reason: correct ? confidence : "wrong")
        }
    }

    func scheduleReview(questionId: String, reason: String) {
        let days = reason == "wrong" ? 1 : (reason == "guess" ? 3 : 7)
        let due = Date().addingTimeInterval(Double(days) * 86400).timeIntervalSince1970
        try? store.execute("INSERT INTO reviews(question_id,due_at,reason,interval_days) VALUES(?,?,?,?) ON CONFLICT(question_id) DO UPDATE SET due_at=excluded.due_at, reason=excluded.reason, interval_days=excluded.interval_days;",
                           bindings: [.text(questionId), .double(due), .text(reason), .int(Int64(days))])
    }

    func pendingReviewQuestions() -> [Question] {
        let rows = (try? store.query("SELECT q.* FROM reviews r JOIN questions q ON q.id=r.question_id WHERE r.due_at <= ? ORDER BY r.due_at ASC;", bindings: [.double(Date().timeIntervalSince1970)])) ?? []
        return rows.compactMap(decodeQuestion)
    }

    func allReviewQuestions() -> [Question] {
        let rows = (try? store.query("SELECT q.* FROM reviews r JOIN questions q ON q.id=r.question_id ORDER BY r.due_at ASC;")) ?? []
        return rows.compactMap(decodeQuestion)
    }

    func dashboardStats() -> DashboardStats {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date()).timeIntervalSince1970
        let today = scalarInt("SELECT COUNT(*) c FROM user_answers WHERE answered_at >= ?;", [.double(start)])
        let total = scalarInt("SELECT COUNT(*) c FROM user_answers;")
        let unique = scalarInt("SELECT COUNT(DISTINCT question_id) c FROM user_answers;")
        let correct = scalarInt("SELECT COUNT(*) c FROM user_answers WHERE is_correct=1;")
        let pending = scalarInt("SELECT COUNT(*) c FROM reviews WHERE due_at <= ?;", [.double(Date().timeIntervalSince1970)])
        return DashboardStats(answeredToday: today, dailyGoal: AppConfig.dailyGoal, totalAnswered: total, uniqueAnswered: unique, correctAnswered: correct, pendingReviews: pending, currentStreak: computeStreak())
    }

    func areaPerformance() -> [AreaPerformance] {
        let rows = (try? store.query("""
        SELECT q.area area, COUNT(a.id) answered, SUM(a.is_correct) correct
        FROM user_answers a JOIN questions q ON q.id=a.question_id
        GROUP BY q.area ORDER BY answered DESC;
        """)) ?? []
        return rows.compactMap { row in
            guard let area = row["area"]?.string else { return nil }
            return AreaPerformance(area: area, answered: Int(row["answered"]?.int ?? 0), correct: Int(row["correct"]?.int ?? 0))
        }
    }

    func latestSimulations(limit: Int = 20) -> [SimulationSummary] {
        let rows = (try? store.query("SELECT * FROM simulations WHERE finished_at IS NOT NULL ORDER BY finished_at DESC LIMIT ?;", bindings: [.int(Int64(limit))])) ?? []
        return rows.compactMap { row in
            guard let id=row["id"]?.string, let title=row["title"]?.string else { return nil }
            return SimulationSummary(id: id, title: title, startedAt: Date(timeIntervalSince1970: row["started_at"]?.double ?? 0), finishedAt: row["finished_at"]?.double.map(Date.init(timeIntervalSince1970:)), score: Int(row["score"]?.int ?? 0), total: Int(row["total"]?.int ?? 0), cutoff: row["cutoff"]?.int.map(Int.init), durationSeconds: Int(row["duration_seconds"]?.int ?? 0), mode: row["mode"]?.string ?? "real")
        }
    }

    func saveSimulation(id: String, title: String, startedAt: Date, finishedAt: Date, score: Int, total: Int, cutoff: Int?, durationSeconds: Int, mode: String, questionIds: [String], answers: [String:String], flags: Set<String>) {
        let ids = (try? String(data: encoder.encode(questionIds), encoding: .utf8)) ?? "[]"
        let ans = (try? String(data: encoder.encode(answers), encoding: .utf8)) ?? "{}"
        let flg = (try? String(data: encoder.encode(Array(flags)), encoding: .utf8)) ?? "[]"
        try? store.execute("INSERT OR REPLACE INTO simulations(id,title,started_at,finished_at,score,total,cutoff,duration_seconds,mode,question_ids_json,answers_json,flags_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);", bindings: [
            .text(id), .text(title), .double(startedAt.timeIntervalSince1970), .double(finishedAt.timeIntervalSince1970), .int(Int64(score)), .int(Int64(total)), cutoff.map { .int(Int64($0)) } ?? .null, .int(Int64(durationSeconds)), .text(mode), .text(ids), .text(ans), .text(flg)
        ])
    }

    func newsItems() -> [NewsItem] {
        let rows = (try? store.query("SELECT * FROM news ORDER BY COALESCE(event_date,published_at) ASC, published_at DESC;")) ?? []
        return rows.compactMap(decodeNews)
    }

    func unreadNewsCount() -> Int { scalarInt("SELECT COUNT(*) c FROM news WHERE is_read=0;") }

    func markAllNewsRead() {
        try? store.execute("UPDATE news SET is_read=1;")
    }

    private func upsert(_ exam: Exam) throws {
        try store.execute("""
        INSERT OR REPLACE INTO exams(id,name,year,edition,board,format_version,objective_questions,discursive_questions,duration_minutes,official_cutoff,exam_date,source_url)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?);
        """, bindings: [.text(exam.id), .text(exam.name), .int(Int64(exam.year)), .text(exam.edition), .text(exam.board), .text(exam.formatVersion), .int(Int64(exam.objectiveQuestions)), .int(Int64(exam.discursiveQuestions)), .int(Int64(exam.durationMinutes)), exam.officialCutoff.map{.int(Int64($0))} ?? .null, exam.examDate.map(SQLiteValue.text) ?? .null, exam.sourceURL.map(SQLiteValue.text) ?? .null])
    }

    private func upsert(_ q: Question) throws {
        let opts = String(data: try encoder.encode(q.options), encoding: .utf8) ?? "[]"
        let exp = q.optionExplanations.flatMap { try? String(data: encoder.encode($0), encoding: .utf8) }
        try store.execute("""
        INSERT OR REPLACE INTO questions(id,exam_id,number,source,year,edition,type,area,specialty,topic,stem,options_json,correct_option,explanation,option_explanations_json,key_point,status,official_source_url)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, bindings: [.text(q.id), q.examId.map(SQLiteValue.text) ?? .null, q.number.map{.int(Int64($0))} ?? .null, .text(q.source), q.year.map{.int(Int64($0))} ?? .null, q.edition.map(SQLiteValue.text) ?? .null, .text(q.type), .text(q.area), q.specialty.map(SQLiteValue.text) ?? .null, q.topic.map(SQLiteValue.text) ?? .null, .text(q.stem), .text(opts), q.correctOption.map(SQLiteValue.text) ?? .null, q.explanation.map(SQLiteValue.text) ?? .null, exp.map(SQLiteValue.text) ?? .null, q.keyPoint.map(SQLiteValue.text) ?? .null, .text(q.status), q.officialSourceURL.map(SQLiteValue.text) ?? .null])
    }

    private func upsert(_ n: NewsItem) throws {
        try store.execute("""
        INSERT INTO news(id,title,body,category,priority,published_at,event_date,end_date,source_url,is_read) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, body=excluded.body, category=excluded.category, priority=excluded.priority, published_at=excluded.published_at, event_date=excluded.event_date, end_date=excluded.end_date, source_url=excluded.source_url;
        """, bindings: [.text(n.id), .text(n.title), .text(n.body), .text(n.category), .text(n.priority), .text(n.publishedAt), n.eventDate.map(SQLiteValue.text) ?? .null, n.endDate.map(SQLiteValue.text) ?? .null, n.sourceURL.map(SQLiteValue.text) ?? .null, .int(n.isRead ? 1 : 0)])
    }

    private func setMetadata(key: String, value: String) throws {
        try store.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;", bindings: [.text(key), .text(value)])
    }

    private func scalarInt(_ sql: String, _ bindings: [SQLiteValue] = []) -> Int {
        Int(((try? store.query(sql, bindings: bindings)) ?? []).first?["c"]?.int ?? 0)
    }

    private func computeStreak() -> Int {
        let rows = (try? store.query("SELECT answered_at FROM user_answers ORDER BY answered_at DESC;")) ?? []
        let days = Set(rows.compactMap { $0["answered_at"]?.double }.map { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: $0)) })
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: Date())
        while days.contains(cursor) { streak += 1; cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)! }
        return streak
    }

    private func decodeExam(_ r: [String: SQLiteValue]) -> Exam? {
        guard let id=r["id"]?.string, let name=r["name"]?.string, let edition=r["edition"]?.string, let board=r["board"]?.string, let fmt=r["format_version"]?.string else { return nil }
        return Exam(id:id,name:name,year:Int(r["year"]?.int ?? 0),edition:edition,board:board,formatVersion:fmt,objectiveQuestions:Int(r["objective_questions"]?.int ?? 0),discursiveQuestions:Int(r["discursive_questions"]?.int ?? 0),durationMinutes:Int(r["duration_minutes"]?.int ?? 0),officialCutoff:r["official_cutoff"]?.int.map(Int.init),examDate:r["exam_date"]?.string,sourceURL:r["source_url"]?.string)
    }

    private func decodeQuestion(_ r: [String: SQLiteValue]) -> Question? {
        guard let id=r["id"]?.string, let source=r["source"]?.string, let type=r["type"]?.string, let area=r["area"]?.string, let stem=r["stem"]?.string, let optionsJSON=r["options_json"]?.string, let status=r["status"]?.string else { return nil }
        let options = (try? decoder.decode([QuestionOption].self, from: Data(optionsJSON.utf8))) ?? []
        var optionExplanations: [String:String]? = nil
        if let json=r["option_explanations_json"]?.string { optionExplanations = try? decoder.decode([String:String].self, from: Data(json.utf8)) }
        return Question(id:id,examId:r["exam_id"]?.string,number:r["number"]?.int.map(Int.init),source:source,year:r["year"]?.int.map(Int.init),edition:r["edition"]?.string,type:type,area:area,specialty:r["specialty"]?.string,topic:r["topic"]?.string,stem:stem,options:options,correctOption:r["correct_option"]?.string,explanation:r["explanation"]?.string,optionExplanations:optionExplanations,keyPoint:r["key_point"]?.string,status:status,officialSourceURL:r["official_source_url"]?.string)
    }

    private func decodeNews(_ r: [String: SQLiteValue]) -> NewsItem? {
        guard let id=r["id"]?.string, let title=r["title"]?.string, let body=r["body"]?.string, let category=r["category"]?.string, let priority=r["priority"]?.string, let pub=r["published_at"]?.string else { return nil }
        return NewsItem(id:id,title:title,body:body,category:category,priority:priority,publishedAt:pub,eventDate:r["event_date"]?.string,endDate:r["end_date"]?.string,sourceURL:r["source_url"]?.string,isRead:(r["is_read"]?.int ?? 0) == 1)
    }
}
