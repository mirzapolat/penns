import Foundation

/// How long a note lives before it archives itself.
public enum Lifespan: String, CaseIterable, Codable, Sendable {
    case untilDone
    case today
    case thisWeek
    /// A date and time the user picked.
    case custom

    /// The presets offered in menus (`custom` has its own picker).
    public static let presets: [Lifespan] = [.untilDone, .today, .thisWeek]

    public var title: String {
        switch self {
        case .untilDone: "Until done"
        case .today: "Today"
        case .thisWeek: "This week"
        case .custom: "Custom"
        }
    }

    /// The moment a note created at `now` expires, or `nil` for `.untilDone`.
    public func expiry(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .untilDone, .custom:
            return nil
        case .today:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.end
        }
    }
}

public enum Lifecycle {
    /// A note untouched this long gets the "Still relevant?" prompt.
    public static let staleInterval: TimeInterval = 7 * 24 * 60 * 60

    public static func isStale(_ note: Note, now: Date) -> Bool {
        guard note.isActive, !note.isBlank else { return false }
        let lastTouch = max(note.updatedAt, note.staleDismissedAt ?? .distantPast)
        return now.timeIntervalSince(lastTouch) >= staleInterval
    }

    /// Today's (or `day`'s) morning reset moment.
    public static func resetMoment(on day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day)) ?? day
    }

    /// The first reset moment strictly after `now`.
    public static func nextResetMoment(after now: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let today = resetMoment(on: now, minutes: minutes, calendar: calendar)
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return resetMoment(on: tomorrow, minutes: minutes, calendar: calendar)
    }

    /// Locale-independent day key, e.g. "2026-11-03".
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Short label such as "today", "until 18:00", "until Sun".
    public static func expiryLabel(_ expiresAt: Date, now: Date, calendar: Calendar = .current) -> String {
        guard expiresAt > now else { return "expired" }
        let lastMoment = expiresAt.addingTimeInterval(-1)
        if calendar.isDate(lastMoment, inSameDayAs: now) {
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            if expiresAt == endOfDay { return "today" }
            return "until " + expiresAt.formatted(.dateTime.hour().minute())
        }
        // Midnight means "through the previous day"; any other time is shown.
        let isMidnight = expiresAt == calendar.startOfDay(for: expiresAt)
        let time = isMidnight ? "" : " " + expiresAt.formatted(.dateTime.hour().minute())
        let day = isMidnight ? lastMoment : expiresAt
        let days = calendar.dateComponents([.day], from: now, to: expiresAt).day ?? 0
        if days < 7 {
            return "until " + day.formatted(.dateTime.weekday(.abbreviated)) + time
        }
        return "until " + day.formatted(.dateTime.day().month(.abbreviated)) + time
    }
}
