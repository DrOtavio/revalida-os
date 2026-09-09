import Foundation

struct Exam: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let year: Int
    let edition: String
    let board: String
    let formatVersion: String
    let objectiveQuestions: Int
    let discursiveQuestions: Int
    let durationMinutes: Int
    let officialCutoff: Int?
    let examDate: String?
    let sourceURL: String?
}

struct QuestionOption: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let text: String
}

struct Question: Identifiable, Codable, Hashable {
    let id: String
    let examId: String?
    let number: Int?
    let source: String
    let year: Int?
    let edition: String?
    let type: String
    let area: String
    let specialty: String?
    let topic: String?
    let stem: String
    let options: [QuestionOption]
    let correctOption: String?
    let explanation: String?
    let optionExplanations: [String: String]?
    let keyPoint: String?
    let status: String
    let officialSourceURL: String?
}

struct NewsItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let body: String
    let category: String
    let priority: String
    let publishedAt: String
    let eventDate: String?
    let endDate: String?
    let sourceURL: String?
    var isRead: Bool = false
}

struct ContentPack: Codable {
    let version: Int
    let generatedAt: String
    let exams: [Exam]
    let questions: [Question]
    let news: [NewsItem]
}

struct ContentManifest: Codable {
    let version: Int
    let generatedAt: String
    let packURL: String
    let sha256: String?
    let notes: String?
}

struct AnswerRecord: Identifiable, Hashable {
    let id: Int64
    let questionId: String
    let selectedOption: String
    let isCorrect: Bool
    let answeredAt: Date
    let responseSeconds: Int
    let confidence: String
}

struct SimulationSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let startedAt: Date
    let finishedAt: Date?
    let score: Int
    let total: Int
    let cutoff: Int?
    let durationSeconds: Int
    let mode: String
}

struct AreaPerformance: Identifiable, Hashable {
    var id: String { area }
    let area: String
    let answered: Int
    let correct: Int
    var percentage: Double { answered == 0 ? 0 : Double(correct) / Double(answered) * 100 }
}

struct DashboardStats {
    let answeredToday: Int
    let dailyGoal: Int
    let totalAnswered: Int
    let scorableAnswered: Int
    let uniqueAnswered: Int
    let correctAnswered: Int
    let pendingReviews: Int
    let currentStreak: Int
    var accuracy: Double { scorableAnswered == 0 ? 0 : Double(correctAnswered) / Double(scorableAnswered) * 100 }
}

extension Question {
    var isAnnulled: Bool { status.lowercased() == "annulled" }

    var displayTopic: String {
        if let topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return topic }
        if let specialty, !specialty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return specialty }
        if area.lowercased() != "não classificada" { return area }
        return "Tema não informado"
    }

    var displayCategory: String {
        var parts: [String] = []
        if area.lowercased() != "não classificada" { parts.append(area) }
        if let specialty, !specialty.isEmpty, specialty != area { parts.append(specialty) }
        return parts.isEmpty ? "Classificação pendente" : parts.joined(separator: " • ")
    }

    var sourceEditionLabel: String {
        var parts = [source]
        if let edition, !edition.isEmpty {
            parts.append(edition.replacingOccurrences(of: "/", with: "-"))
        } else if let year {
            parts.append(String(year))
        }
        return parts.joined(separator: " • ")
    }
}
