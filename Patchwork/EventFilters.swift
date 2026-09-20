// SPDX-License-Identifier: MPL-2.0

import Foundation

/// The events list's date presets, ported from the web's `eventDateRange`
/// (web/src/lib/datetime.js) so the two surfaces name the same days.
///
/// A calendar day is a span in some zone, and the API compares `starts_at`
/// as text, so a day filter travels as the two instants that bound it: a
/// bare `2026-07-26` sorts *before* every timestamp on 2026-07-26, and
/// sending it as `to` drops the day it names. The zone is the quilt's
/// (`instance.geography.timezone`), not the reader's — "tonight" on a
/// Lancaster calendar means Lancaster's night wherever it is read from.
enum EventDatePreset: String, CaseIterable, Identifiable, Hashable {
    case any, today, tomorrow, weekend, week, nextweek, month, custom
    var id: String { rawValue }
    /// The presets the menu offers directly; `custom` arrives through its
    /// own picker and never sits in the list.
    static var offered: [EventDatePreset] { [.any, .today, .tomorrow, .weekend, .week, .nextweek, .month] }
    var label: String {
        switch self {
        case .any: return "Any date"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .weekend: return "This weekend"
        case .week: return "This week"
        case .nextweek: return "Next week"
        case .month: return "This month"
        case .custom: return "Custom range"
        }
    }
}

/// A preset plus the two dates a custom range names.
struct EventDateFilter: Equatable {
    var preset: EventDatePreset = .any
    var customFrom: Date? = nil
    var customTo: Date? = nil
    var isActive: Bool { preset != .any }
    func label(timeZone: TimeZone) -> String {
        guard preset == .custom else { return preset.label }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch (customFrom, customTo) {
        case let (from?, to?): return "\(formatter.string(from: from)) – \(formatter.string(from: to))"
        case let (from?, nil): return "From \(formatter.string(from: from))"
        default: return EventDatePreset.custom.label
        }
    }
}

/// The instants a preset resolves to. Pure, and `now` is injectable, so the
/// boundary rules can be pinned against a fixed day.
enum EventDateBounds {
    /// `from` is always sent; `to` is nil where the range has no upper edge.
    static func resolve(_ filter: EventDateFilter, now: Date = Date(), timeZone: TimeZone) -> (from: String, to: String?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)

        func shift(_ base: Date, _ days: Int) -> Date {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: base) ?? base)
        }
        func dayStart(_ date: Date) -> String { instant(calendar.startOfDay(for: date)) }
        /// The last second of a day, inclusive, because the API's `to` is
        /// `<=`. Derived from the next day's midnight rather than by adding
        /// 24 hours, so a 23- or 25-hour day still ends where it should, and
        /// emitted without a fraction: `starts_at` holds two precisions and
        /// the comparison is text, where 'Z' sorts after '.'.
        func dayEnd(_ date: Date) -> String { instant(shift(date, 1).addingTimeInterval(-1)) }

        // Weeks start on Monday, so a weekend is the tail of one week rather
        // than a thing split across two. Foundation counts weekdays from
        // Sunday (1); this counts from Monday (0), which is what keeps the
        // week's edges from leaving Sunday in a gap neither preset reaches.
        let isoWeekday = (calendar.component(.weekday, from: today) + 5) % 7

        switch filter.preset {
        case .today:
            return (dayStart(today), dayEnd(today))
        case .tomorrow:
            let tomorrow = shift(today, 1)
            return (dayStart(tomorrow), dayEnd(tomorrow))
        case .weekend:
            // This week's weekend, never next week's. On Sunday that weekend
            // has already begun, so it starts today rather than yesterday.
            let saturday = shift(today, 5 - isoWeekday)
            let start = saturday < today ? today : saturday
            return (dayStart(start), dayEnd(shift(saturday, 1)))
        case .week:
            // Today through Sunday. On Sunday that is today alone, which is
            // honest: Sunday ends its week rather than starting the next.
            return (dayStart(today), dayEnd(shift(today, 6 - isoWeekday)))
        case .nextweek:
            // The Monday after this week's Sunday, so the two presets meet.
            let monday = shift(today, 7 - isoWeekday)
            return (dayStart(monday), dayEnd(shift(monday, 6)))
        case .month:
            let days = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            let day = calendar.component(.day, from: today)
            return (dayStart(today), dayEnd(shift(today, days - day)))
        case .custom:
            let from = filter.customFrom ?? today
            return (dayStart(from), filter.customTo.map(dayEnd))
        case .any:
            return (dayStart(today), nil)
        }
    }

    private static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
