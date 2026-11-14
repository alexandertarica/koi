import Foundation
import UserNotifications
import OSLog

enum KoiNotificationMode: String, CaseIterable, Identifiable {
    case smart
    case onceDaily
    case none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: "Smart"
        case .onceDaily: "Once a day"
        case .none: "None"
        }
    }
}

struct NotificationReminder: Sendable {
    let id: String
    let title: String
    let date: Date
    let repeatsWeekday: Int?
    let repeatsDaily: Bool
}

@MainActor
protocol NotificationProviding: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replaceScheduledReminders(_ reminders: [NotificationReminder], dailyCheckInHour: Int?) async throws
    func removeReminder(id: String)
}

@MainActor
final class NotificationService: NotificationProviding {
    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Notifications")
    private let prefix = "com.alexandertarica.koi."

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func replaceScheduledReminders(_ reminders: [NotificationReminder], dailyCheckInHour: Int?) async throws {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) })

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }
        for reminder in reminders where reminder.repeatsDaily || reminder.repeatsWeekday != nil || reminder.date > .now {
            let content = UNMutableNotificationContent()
            content.title = "Koi"
            content.body = reminder.title
            content.sound = .default
            let trigger: UNNotificationTrigger
            if reminder.repeatsDaily {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: reminder.date)
                trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            } else if let weekday = reminder.repeatsWeekday {
                var parts = Calendar.current.dateComponents([.hour, .minute], from: reminder.date)
                parts.weekday = weekday
                trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date), repeats: false)
            }
            let request = UNNotificationRequest(identifier: prefix + reminder.id, content: content, trigger: trigger)
            try await center.add(request)
        }

        if let hour = dailyCheckInHour, (0...23).contains(hour) {
            let content = UNMutableNotificationContent()
            content.title = "A moment for your day"
            content.body = "Your Koi check-in is ready."
            content.sound = .default
            var parts = DateComponents()
            parts.hour = hour
            parts.minute = 0
            try await center.add(UNNotificationRequest(identifier: prefix + "daily-check-in", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
        }
    }

    func removeReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [prefix + id])
        center.removeDeliveredNotifications(withIdentifiers: [prefix + id])
    }
}
