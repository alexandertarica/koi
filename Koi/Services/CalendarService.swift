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

@MainActor
protocol CalendarProviding: Sendable {
    var isAvailable: Bool { get }
    func requestAccess() async throws
    func saveTaskEvent(_ task: CalendarTaskValue) async throws -> String
    func deleteTaskEvent(identifier: String) async throws
}

enum CalendarServiceError: LocalizedError {
    case unavailable
    case accessDenied
    case eventMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Calendar isn't available on this device."
        case .accessDenied: "Allow Koi to use Calendar in Settings, then try again."
        case .eventMissing: "Couldn't find that calendar event."
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
}
