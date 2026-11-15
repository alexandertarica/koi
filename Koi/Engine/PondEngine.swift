import Foundation

enum PondPillar: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case habits
    case nutrition
    case exercise

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PondMember: Codable, Equatable, Hashable, Identifiable, Sendable {
    let username: String
    let displayName: String

    var id: String { username.lowercased() }
}

struct PondDailyScore: Codable, Equatable, Identifiable, Sendable {
    let username: String
    let dayKey: String
    var habits: Double
    var nutrition: Double
    var exercise: Double

    var id: String { "\(username.lowercased())-\(dayKey)" }

    subscript(_ pillar: PondPillar) -> Double {
        get {
            switch pillar {
            case .habits: habits
            case .nutrition: nutrition
            case .exercise: exercise
            }
        }
        set {
            let score = Self.clamped(newValue)
            switch pillar {
            case .habits: habits = score
            case .nutrition: nutrition = score
            case .exercise: exercise = score
            }
        }
    }

    init(username: String, date: Date, habits: Double, nutrition: Double, exercise: Double, calendar: Calendar = .autoupdatingCurrent) {
        self.username = username.lowercased()
        self.dayKey = PondEngine.dayKey(for: date, calendar: calendar)
        self.habits = Self.clamped(habits)
        self.nutrition = Self.clamped(nutrition)
        self.exercise = Self.clamped(exercise)
    }

    init(username: String, dayKey: String, habits: Double, nutrition: Double, exercise: Double) {
        self.username = username.lowercased()
        self.dayKey = dayKey
        self.habits = Self.clamped(habits)
        self.nutrition = Self.clamped(nutrition)
        self.exercise = Self.clamped(exercise)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct PondSprint: Codable, Equatable, Identifiable, Sendable {
    let recordName: String
    var pillars: Set<PondPillar>
    let startDate: Date
    var endDate: Date
    var rule: String
    let createdBy: String

    var id: String { recordName }
    var isFinished: Bool { Date.now >= endDate }
}

struct PondSnapshot: Codable, Equatable, Sendable {
    var currentUsername: String
    var name: String
    var members: [PondMember]
    var sprint: PondSprint?
    var dailyScores: [PondDailyScore]
}

struct PondLeaderboardEntry: Equatable, Identifiable, Sendable {
    let member: PondMember
    let score: Double
    let rank: Int

    var id: String { member.id }
}

enum PondEngine {
    static func isValidUsername(_ username: String) -> Bool {
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...20).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar.value == 95
        }
    }

    static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func dateKeys(from start: Date, through end: Date, calendar: Calendar = .autoupdatingCurrent) -> [String] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [] }
        var keys: [String] = []
        var cursor = first
        while cursor <= last {
            keys.append(dayKey(for: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return keys
    }

    static func score(for username: String, sprint: PondSprint, scores: [PondDailyScore], through date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Double {
        guard !sprint.pillars.isEmpty else { return 0 }
        let lastDate = min(date, sprint.endDate)
        let days = dateKeys(from: sprint.startDate, through: lastDate, calendar: calendar)
        guard !days.isEmpty else { return 0 }
        let canonical = username.lowercased()
        let scoreByDay = Dictionary(scores.filter { $0.username.lowercased() == canonical }.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let total = days.reduce(0.0) { sum, day in
            guard let daily = scoreByDay[day] else { return sum }
            return sum + sprint.pillars.reduce(0.0) { $0 + daily[$1] }
        }
        return min(max(total / Double(days.count * sprint.pillars.count), 0), 1)
    }

    static func leaderboard(for snapshot: PondSnapshot, through date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [PondLeaderboardEntry] {
        guard let sprint = snapshot.sprint else { return [] }
        let ranked = snapshot.members.map { member in
            (member, score(for: member.username, sprint: sprint, scores: snapshot.dailyScores, through: date, calendar: calendar))
        }.sorted { left, right in
            if abs(left.1 - right.1) > 0.000_000_1 { return left.1 > right.1 }
            return left.0.displayName.localizedCaseInsensitiveCompare(right.0.displayName) == .orderedAscending
        }
        return ranked.enumerated().map { index, item in
            PondLeaderboardEntry(member: item.0, score: item.1, rank: index + 1)
        }
    }

    static func winner(for snapshot: PondSnapshot, through date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> PondLeaderboardEntry? {
        guard let sprint = snapshot.sprint, date >= sprint.endDate else { return nil }
        return leaderboard(for: snapshot, through: sprint.endDate, calendar: calendar).first
    }

    static func nextThursday(after date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let days = (5 - weekday + 7) % 7
        let offset = days == 0 ? 7 : days
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func daysRemaining(until endDate: Date, from date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }
}
