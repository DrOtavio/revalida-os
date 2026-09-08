import Foundation
import UserNotifications

@MainActor
enum NotificationScheduler {
    static func requestAndSchedule(items: [NewsItem]) async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return false }
            center.removePendingNotificationRequests(withIdentifiers: items.flatMap { ids(for: $0) })
            for item in items { await schedule(item, center: center) }
            return true
        } catch { return false }
    }

    private static func schedule(_ item: NewsItem, center: UNUserNotificationCenter) async {
        guard let raw = item.eventDate, let date = parse(raw) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        for daysBefore in [7, 1, 0] {
            guard let targetDay = Calendar.current.date(byAdding: .day, value: -daysBefore, to: date), targetDay >= today else { continue }
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: targetDay)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = daysBefore == 0 ? item.title : "\(item.title) em \(daysBefore) \(daysBefore == 1 ? "dia" : "dias")"
            content.body = item.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(item.id)-\(daysBefore)", content: content, trigger: trigger))
        }
        if let endRaw = item.endDate, let end = parse(endRaw), end >= today {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: end)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = "Último dia: \(item.title)"
            content.body = "Prazo termina hoje."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "\(item.id)-deadline", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    private static func parse(_ raw: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    private static func ids(for item: NewsItem) -> [String] { ["\(item.id)-7", "\(item.id)-1", "\(item.id)-0", "\(item.id)-deadline"] }
}
