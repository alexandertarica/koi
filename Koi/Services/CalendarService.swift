import EventKit
import Foundation
import OSLog

struct CalendarTaskValue: Sendable {
    let id: UUID
    let title: String
    let notes: String
    let start: Date
    let durationMinutes: Int
    let eventIdentifier: String?
}

struct ReminderTaskValue: Sendable {
    let id: UUID
    let title: String
    let notes: String
    let dueAt: Date
    let reminderIdentifier: String?
}

struct CalendarEventSummary: Sendable {
    let title: String
    let start: Date
    let end: Date
}

@MainActor
protocol CalendarProviding: Sendable {
    var isAvailable: Bool { get }
    func requestAccess() async throws
    func saveTaskEvent(_ task: CalendarTaskValue) async throws -> String
    func deleteTaskEvent(identifier: String) async throws
    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary]
    func requestReminderAccess() async throws
    func saveTaskReminder(_ task: ReminderTaskValue) async throws -> String
    func deleteTaskReminder(identifier: String) async throws
}

extension CalendarProviding {
    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary] { [] }
    func requestReminderAccess() async throws { throw CalendarServiceError.unavailable }
    func saveTaskReminder(_ task: ReminderTaskValue) async throws -> String { throw CalendarServiceError.unavailable }
    func deleteTaskReminder(identifier: String) async throws {}
}

enum CalendarServiceError: LocalizedError {
    case unavailable
    case accessDenied
    case eventMissing
    case reminderMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Calendar isn't available on this device."
        case .accessDenied: "Allow Koi to use Calendar in Settings, then try again."
        case .eventMissing: "Couldn't find that calendar event."
        case .reminderMissing: "Couldn't save that Apple Reminder."
        }
    }
}

@MainActor
final class CalendarService: CalendarProviding {
    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Calendar")
    var isAvailable: Bool { EKEventStore.authorizationStatus(for: .event) != .restricted }

    func requestAccess() async throws {
        guard isAvailable else { throw CalendarServiceError.unavailable }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .writeOnly { return }
        let allowed = try await store.requestFullAccessToEvents()
        guard allowed else { throw CalendarServiceError.accessDenied }
    }

    func saveTaskEvent(_ task: CalendarTaskValue) async throws -> String {
        try await requestAccess()
        let event = task.eventIdentifier.flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        event.title = task.title
        event.notes = task.notes.isEmpty ? nil : task.notes
        event.startDate = task.start
        event.endDate = task.start.addingTimeInterval(TimeInterval(max(task.durationMinutes, 5) * 60))
        try store.save(event, span: .thisEvent, commit: true)
        guard let identifier = event.eventIdentifier else { throw CalendarServiceError.eventMissing }
        return identifier
    }

    func deleteTaskEvent(identifier: String) async throws {
        try await requestAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEventSummary(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate) }
    }

    func requestReminderAccess() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) != .restricted else { throw CalendarServiceError.unavailable }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { return }
        guard try await store.requestFullAccessToReminders() else { throw CalendarServiceError.accessDenied }
    }

    func saveTaskReminder(_ task: ReminderTaskValue) async throws -> String {
        try await requestReminderAccess()
        let reminder = task.reminderIdentifier.flatMap(store.calendarItem(withIdentifier:)) as? EKReminder ?? EKReminder(eventStore: store)
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.title = task.title
        reminder.notes = task.notes.isEmpty ? nil : task.notes
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueAt)
        try store.save(reminder, commit: true)
        guard let identifier = reminder.calendarItemIdentifier as String? else { throw CalendarServiceError.reminderMissing }
        return identifier
    }

    func deleteTaskReminder(identifier: String) async throws {
        try await requestReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }
}
