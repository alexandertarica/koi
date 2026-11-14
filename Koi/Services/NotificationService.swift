import Foundation
import UserNotifications
import OSLog
import SwiftData
import KoiShared

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
    var notificationTitle: String = "Koi"
    var tab: Int = 0
    var pillar: String? = nil
}

enum NotificationPlanner {
    static func checkIns(hour: Int, now: Date, calendar input: Calendar = .autoupdatingCurrent) -> [NotificationReminder] {
        guard (8...20).contains(hour) else { return [] }
        var calendar = input
        calendar.timeZone = .autoupdatingCurrent
        var reminders: [NotificationReminder] = []
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), fire > now else { continue }
            let sunday = calendar.component(.weekday, from: day) == 1
            reminders.append(NotificationReminder(
                id: "check-in-\(reminders.count)",
                title: reminders.isEmpty && !sunday ? "A quiet moment to check in with your balance." : sunday ? "Your week in review is ready." : "Your Koi check-in is ready.",
                date: fire,
                repeatsWeekday: nil,
                repeatsDaily: false,
                notificationTitle: sunday ? "Your week" : "Daily check-in",
                tab: 0
            ))
            if reminders.count == 7 { break }
        }
        return reminders
    }

    static func morningContent(yesterdayScore: Double?, suggestion: String?) -> (title: String, body: String) {
        guard let yesterdayScore, yesterdayScore > 0 else { return ("Daily check-in", "A quiet moment to check in with your balance.") }
        let scoreText = "Yesterday \(Int((min(max(yesterdayScore, 0), 1) * 100).rounded()))%."
        return ("Daily check-in", [scoreText, suggestion].compactMap { $0 }.joined(separator: " "))
    }

    static func recapContent(average: Double, bestDay: String?) -> (title: String, body: String) {
        guard average > 0, let bestDay else { return ("Your week", "Your week in review is ready.") }
        return ("Your week", "\(Int((min(max(average, 0), 1) * 100).rounded()))% average, best day \(bestDay). Tap to see it.")
    }

    static func habitReminders(habits: [KoiHabit], logs: [KoiHabitLog], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [NotificationReminder] {
        habits.filter { $0.isActive && $0.pausedAt == nil && $0.graduatedAt == nil }.flatMap { habit -> [NotificationReminder] in
            guard let reminderTime = habit.reminderTime else { return [] }
            let weekdays = habit.schedule == "daily" ? Array(1...7) : habit.schedule == "someDays" ? habit.weekdays : [calendar.component(.weekday, from: habit.createdAt)]
            return weekdays.compactMap { weekday -> NotificationReminder? in
                let today = calendar.component(.weekday, from: now)
                guard weekday == today,
                      !logs.contains(where: { $0.habitID == habit.id && calendar.isDate($0.date, inSameDayAs: now) && $0.completion > 0 }) else { return nil }
                let parts = calendar.dateComponents([.hour, .minute], from: reminderTime)
                guard let scheduled = calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: now) else { return nil }
                let fire = scheduled.addingTimeInterval(-10 * 60)
                guard fire > now else { return nil }
                return NotificationReminder(id: "habit-\(habit.id.uuidString)-\(weekday)", title: "In 10 minutes, time for \(habit.title).", date: fire, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: habit.title, tab: 1)
            }
        }
    }

    static func scheduleTime(from reminderTime: Date, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: reminderTime)
        return calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: date)
    }
}

@MainActor
protocol NotificationProviding: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replaceScheduledReminders(_ reminders: [NotificationReminder], dailyCheckInHour: Int?) async throws
    func removeReminder(id: String)
    func refreshPlan(using context: ModelContext) async
}

final class KoiNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let didOpen = Notification.Name("KoiNotificationDidOpen")

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationCenter.default.post(name: Self.didOpen, object: nil, userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
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
            content.title = reminder.notificationTitle
            content.body = reminder.title
            content.sound = .default
            var info: [AnyHashable: Any] = ["tab": reminder.tab]
            if let pillar = reminder.pillar { info["pillar"] = pillar }
            content.userInfo = info
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

        guard let hour = dailyCheckInHour else { return }
        let checkIns = NotificationPlanner.checkIns(hour: hour, now: .now)
        for reminder in checkIns {
            let content = UNMutableNotificationContent()
            content.title = reminder.notificationTitle
            content.body = reminder.title
            content.sound = .default
            content.userInfo = ["tab": reminder.tab]
            let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            try await center.add(UNNotificationRequest(identifier: prefix + reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    func removeReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [prefix + id])
        center.removeDeliveredNotifications(withIdentifiers: [prefix + id])
    }

    func refreshPlan(using context: ModelContext) async {
        do {
            let settings = try context.fetch(FetchDescriptor<KoiOnboardingState>()).first
            let mode = KoiNotificationMode(rawValue: settings?.notificationMode ?? "smart") ?? .smart
            guard mode != .none else {
                try await replaceScheduledReminders([], dailyCheckInHour: nil)
                return
            }
            var reminders = NotificationPlanner.checkIns(hour: settings?.dailyCheckInHour ?? 9, now: .now)
            if mode == .smart {
                let habits = try context.fetch(FetchDescriptor<KoiHabit>())
                let logs = try context.fetch(FetchDescriptor<KoiHabitLog>())
                reminders += NotificationPlanner.habitReminders(habits: habits, logs: logs, now: .now)
                let tasks = try context.fetch(FetchDescriptor<KoiTask>()).filter { !$0.isComplete && $0.archivedAt == nil && $0.hasTime && $0.timeMinutes > 0 }
                for task in tasks {
                    guard let dueAt = task.dueAt else { continue }
                    let fire = dueAt.addingTimeInterval(-10 * 60)
                    guard fire > .now else { continue }
                    reminders.append(NotificationReminder(id: "task-\(task.id.uuidString)", title: "In 10 minutes, \(task.title).", date: fire, repeatsWeekday: nil, repeatsDaily: false, notificationTitle: "Coming up", tab: 1))
                }
            }
            try await replaceScheduledReminders(Array(reminders.prefix(60)), dailyCheckInHour: nil)
        } catch {
            logger.error("Unable to replan notifications.")
        }
    }
}
