import Foundation

struct ParsedDate: Equatable, Sendable {
    let date: Date
    let matchedText: String
}

enum DateParsing {
    private static let weekdayNames = [
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
        "sunday": 1, "sun": 1
    ]

    static func parse(_ text: String, relativeTo now: Date, calendar inputCalendar: Calendar = .autoupdatingCurrent) -> ParsedDate? {
        let calendar = inputCalendar
        let lowercased = text.lowercased()
        let timeMatch = findTime(in: lowercased)
        let containsClockExpression = lowercased.range(of: #"\bat\s+\d+"#, options: .regularExpression) != nil
        guard timeMatch != nil || !containsClockExpression else { return nil }
        let dayMatch = findDay(in: lowercased, now: now, calendar: calendar)
        guard dayMatch != nil || timeMatch != nil else { return nil }

        var day = calendar.startOfDay(for: now)
        if let delta = dayMatch?.dayOffset {
            guard let moved = calendar.date(byAdding: .day, value: delta, to: day) else { return nil }
            day = moved
        } else if let weekday = dayMatch?.weekday,
                  let target = calendar.nextDate(after: day, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime, direction: .forward) {
            day = calendar.startOfDay(for: target)
        }

        var result = day
        var matchedText = dayMatch?.text ?? ""
        if let timeMatch {
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = timeMatch.hour
            parts.minute = timeMatch.minute
            guard let timed = calendar.date(from: parts) else { return nil }
            result = timed
            if dayMatch == nil, timed <= now {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
                var tomorrowParts = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                tomorrowParts.hour = timeMatch.hour
                tomorrowParts.minute = timeMatch.minute
                guard let tomorrowTime = calendar.date(from: tomorrowParts) else { return nil }
                result = tomorrowTime
            }
            matchedText = [matchedText, timeMatch.text].filter { !$0.isEmpty }.joined(separator: " ")
        }

        return ParsedDate(date: result, matchedText: matchedText)
    }

    private struct DayMatch {
        let text: String
        let dayOffset: Int?
        let weekday: Int?
    }

    private static func findDay(in text: String, now: Date, calendar: Calendar) -> DayMatch? {
        if let range = text.range(of: #"\btoday\b"#, options: .regularExpression) {
            return DayMatch(text: String(text[range]), dayOffset: 0, weekday: nil)
        }
        if let range = text.range(of: #"\btomorrow\b"#, options: .regularExpression) {
            return DayMatch(text: String(text[range]), dayOffset: 1, weekday: nil)
        }

        let todayWeekday = calendar.component(.weekday, from: now)
        for (name, targetWeekday) in weekdayNames.sorted(by: { $0.key.count > $1.key.count }) {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let delta = (targetWeekday - todayWeekday + 7) % 7
            let nextOccurrence = delta == 0 ? 7 : delta
            return DayMatch(text: String(text[range]), dayOffset: nextOccurrence, weekday: nil)
        }
        return nil
    }

    private struct TimeMatch {
        let text: String
        let hour: Int
        let minute: Int
    }

    private static func findTime(in text: String) -> TimeMatch? {
        let pattern = #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let fullRange = Range(match.range, in: text),
              let hourRange = Range(match.range(at: 1), in: text),
              let hourValue = Int(text[hourRange]) else { return nil }

        let minute: Int
        if let minuteRange = Range(match.range(at: 2), in: text), let value = Int(text[minuteRange]) {
            minute = value
        } else {
            minute = 0
        }
        guard let periodRange = Range(match.range(at: 3), in: text), (1...12).contains(hourValue), (0..<60).contains(minute) else { return nil }
        let period = text[periodRange]
        let hour = hourValue % 12 + (period == "pm" ? 12 : 0)
        return TimeMatch(text: String(text[fullRange]), hour: hour, minute: minute)
    }
}
