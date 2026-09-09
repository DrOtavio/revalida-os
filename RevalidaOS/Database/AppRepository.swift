import Foundation

final class AppRepository {
    private let store: SQLiteStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: SQLiteStore) { self.store = store }

    func prepareDatabase() throws {
        try store.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);")
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
        try ensureColumn(table: "questions", column: "media_json", definition: "TEXT")
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
        try ensureColumn(table: "user_answers", column: "scorable", definition: "INTEGER NOT NULL DEFAULT 1")
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
        try importPack(data: Data(contentsOf: url))
    }

    func importPack(data: Data) throws {
        let pack = try decoder.decode(ContentPack.self, from: data)
        try store.transaction {
            for exam in pack.exams { try upsert(exam) }
            for question in pack.questions { try upsert(question) }
            for news in pack.news { try upsert(news) }
            try store.execute("UPDATE user_answers SET scorable=0 WHERE question_id IN (SELECT id FROM questions WHERE status='annulled' OR correct_option IS NULL);")
            try store.execute("DELETE FROM reviews WHERE question_id IN (SELECT id FROM questions WHERE status='annulled' OR correct_option IS NULL);")
            try setMetadata(key: "content_version", value: String(pack.version))
            try setMetadata(key: "content_generated_at", value: pack.generatedAt)
        }
    }

    func contentVersion() -> Int {
        (try? store.query("SELECT value FROM metadata WHERE key='content_version' LIMIT 1;").first?["value"]?.string.flatMap(Int.init)) ?? 0
    }

    func allQuestions(area: String? = nil, source: String? = nil, limit: Int = 5000) -> [Question] {
        var sql = "SELECT * FROM questions WHERE 1=1"
        var bind: [SQLiteValue] = []
        if let area, !area.isEmpty { sql += " AND area=?"; bind.append(.text(area)) }
        if let source, !source.isEmpty { sql += " AND source=?"; bind.append(.text(source)) }
        sql += " ORDER BY COALESCE(year,0) DESC, COALESCE(number,0) ASC LIMIT ?;"
        bind.append(.int(Int64(limit)))
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

    func recordAnswer(question: Question, selected: String, seconds: Int, confidence: String) {
        let isCorrect = !question.isAnnulled && selected == question.correctOption
        let scorable = (!question.isAnnulled && question.correctOption != nil) ? 1 : 0
        try? store.execute("""
        INSERT INTO user_answers(question_id, selected_option, is_correct, answered_at, response_seconds, confidence, scorable)
        VALUES(?,?,?,?,?,?,?);
        """, bindings: [
            .text(question.id), .text(selected), .int(isCorrect ? 1 : 0),
            .double(Date().timeIntervalSince1970), .int(Int64(seconds)), .text(confidence), .int(Int64(scorable))
        ])
    }

    func scheduleReview(questionId: String, reason: String) {
        let due = Date().timeIntervalSince1970
        try? store.execute("""
        INSERT INTO reviews(question_id,due_at,reason,interval_days) VALUES(?,?,?,1)
        ON CONFLICT(question_id) DO UPDATE SET due_at=excluded.due_at, reason=excluded.reason;
        """, bindings: [.text(questionId), .double(due), .text(reason)])
    }

    private func upsert(_ exam: Exam) throws {
        try store.execute("""
        INSERT OR REPLACE INTO exams(id,name,year,edition,board,format_version,objective_questions,discursive_questions,duration_minutes,official_cutoff,exam_date,source_url)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?);
        """, bindings: [
            .text(exam.id), .text(exam.name), .int(Int64(exam.year)), .text(exam.edition), .text(exam.board),
            .text(exam.formatVersion), .int(Int64(exam.objectiveQuestions)), .int(Int64(exam.discursiveQuestions)),
            .int(Int64(exam.durationMinutes)), exam.officialCutoff.map { .int(Int64($0)) } ?? .null,
            exam.examDate.map(SQLiteValue.text) ?? .null, exam.sourceURL.map(SQLiteValue.text) ?? .null
        ])
    }

    private func upsert(_ q: Question) throws {
        let opts = String(data: try encoder.encode(q.options), encoding: .utf8) ?? "[]"
        let exp = q.optionExplanations.flatMap { try? String(data: encoder.encode($0), encoding: .utf8) }
        let media = q.media.flatMap { try? String(data: encoder.encode($0), encoding: .utf8) }
        try store.execute("""
        INSERT OR REPLACE INTO questions(id,exam_id,number,source,year,edition,type,area,specialty,topic,stem,options_json,correct_option,explanation,option_explanations_json,key_point,status,official_source_url,media_json)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """, bindings: [
            .text(q.id), q.examId.map(SQLiteValue.text) ?? .null, q.number.map { .int(Int64($0)) } ?? .null,
            .text(q.source), q.year.map { .int(Int64($0)) } ?? .null, q.edition.map(SQLiteValue.text) ?? .null,
            .text(q.type), .text(q.area), q.specialty.map(SQLiteValue.text) ?? .null,
            q.topic.map(SQLiteValue.text) ?? .null, .text(q.stem), .text(opts),
            q.correctOption.map(SQLiteValue.text) ?? .null, q.explanation.map(SQLiteValue.text) ?? .null,
            exp.map(SQLiteValue.text) ?? .null, q.keyPoint.map(SQLiteValue.text) ?? .null,
            .text(q.status), q.officialSourceURL.map(SQLiteValue.text) ?? .null, media.map(SQLiteValue.text) ?? .null
        ])
    }

    private func upsert(_ n: NewsItem) throws {
        try store.execute("""
        INSERT INTO news(id,title,body,category,priority,published_at,event_date,end_date,source_url,is_read) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, body=excluded.body, category=excluded.category, priority=excluded.priority, published_at=excluded.published_at, event_date=excluded.event_date, end_date=excluded.end_date, source_url=excluded.source_url;
        """, bindings: [
            .text(n.id), .text(n.title), .text(n.body), .text(n.category), .text(n.priority),
            .text(n.publishedAt), n.eventDate.map(SQLiteValue.text) ?? .null,
            n.endDate.map(SQLiteValue.text) ?? .null, n.sourceURL.map(SQLiteValue.text) ?? .null,
            .int(n.isRead ? 1 : 0)
        ])
    }

    private func setMetadata(key: String, value: String) throws {
        try store.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;", bindings: [.text(key), .text(value)])
    }

    private func ensureColumn(table: String, column: String, definition: String) throws {
        let rows = try store.query("PRAGMA table_info(\(table));")
        let exists = rows.contains { $0["name"]?.string == column }
        if !exists {
            try store.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        }
    }

    private func decodeQuestion(_ r: [String: SQLiteValue]) -> Question? {
        guard
            let id = r["id"]?.string,
            let source = r["source"]?.string,
            let type = r["type"]?.string,
            let area = r["area"]?.string,
            let stem = r["stem"]?.string,
            let optionsJSON = r["options_json"]?.string,
            let status = r["status"]?.string
        else { return nil }

        let options = (try? decoder.decode([QuestionOption].self, from: Data(optionsJSON.utf8))) ?? []
        let optionExplanations: [String: String]? = r["option_explanations_json"]?.string.flatMap {
            try? decoder.decode([String: String].self, from: Data($0.utf8))
        }
        let media: [QuestionMedia]? = r["media_json"]?.string.flatMap {
            try? decoder.decode([QuestionMedia].self, from: Data($0.utf8))
        }

        return Question(
            id: id,
            examId: r["exam_id"]?.string,
            number: r["number"]?.int.map(Int.init),
            source: source,
            year: r["year"]?.int.map(Int.init),
            edition: r["edition"]?.string,
            type: type,
            area: area,
            specialty: r["specialty"]?.string,
            topic: r["topic"]?.string,
            stem: stem,
            options: options,
            correctOption: r["correct_option"]?.string,
            explanation: r["explanation"]?.string,
            optionExplanations: optionExplanations,
            keyPoint: r["key_point"]?.string,
            status: status,
            officialSourceURL: r["official_source_url"]?.string,
            media: media
        )
    }
}
