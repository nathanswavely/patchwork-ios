// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import Patchwork

/// The date presets, pinned against the same fixed days the web pins them
/// against (web/src/test/datetime.test.js). The two surfaces have to name
/// the same span or a reader who checks both is told two different things.
final class EventDateBoundsTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    private func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    private func range(_ preset: EventDatePreset, now: Date) -> (from: String, to: String?) {
        EventDateBounds.resolve(EventDateFilter(preset: preset), now: now, timeZone: zone)
    }
    /// The comparison the server makes: `starts_at` as text, `to` inclusive.
    private func covers(_ range: (from: String, to: String?), _ moment: Date) -> Bool {
        let value = instant(moment)
        return value >= range.from && (range.to.map { value <= $0 } ?? true)
    }

    /// The bug the web fixed: both bounds were bare dates and `to` is `<=`,
    /// so the named day sorted out of its own range.
    func testASingleDayIsANonEmptySpanThatAdmitsItsOwnEvening() {
        let thursday = at(7, 23, 15, 30)
        for preset in [EventDatePreset.today, .tomorrow] {
            let bounds = range(preset, now: thursday)
            XCTAssertNotNil(bounds.to)
            XCTAssertGreaterThan(bounds.to!, bounds.from, preset.rawValue)
        }
        XCTAssertTrue(covers(range(.today, now: thursday), at(7, 23, 23, 30)))
        XCTAssertTrue(covers(range(.tomorrow, now: thursday), at(7, 24, 23, 59)))
        XCTAssertFalse(covers(range(.today, now: thursday), at(7, 24, 0, 30)))
    }

    /// Mon 20 through Sun 26, read from every day of that week.
    func testThisWeekEndsOnSundayAndNextWeekStartsOnMonday() {
        for day in 20...26 {
            let now = at(7, day, 15, 0)
            let week = range(.week, now: now), next = range(.nextweek, now: now)
            XCTAssertTrue(covers(week, at(7, day)), "day \(day)")
            XCTAssertTrue(covers(week, at(7, 26)), "Sunday from day \(day)")
            XCTAssertFalse(covers(week, at(7, 27)), "next Monday from day \(day)")
            XCTAssertTrue(covers(next, at(7, 27)), "day \(day)")
            XCTAssertTrue(covers(next, at(8, 2)), "day \(day)")
            XCTAssertFalse(covers(next, at(7, 26)), "day \(day)")
            XCTAssertFalse(covers(next, at(8, 3)), "day \(day)")
        }
    }

    /// The regression that motivated the web's pass: no day between the two
    /// presets may be unreachable.
    func testNoDayFallsBetweenThisWeekAndNextWeek() {
        for day in 20...26 {
            let now = at(7, day, 15, 0)
            let week = range(.week, now: now), next = range(.nextweek, now: now)
            for target in day...31 {
                XCTAssertTrue(covers(week, at(7, target)) || covers(next, at(7, target)), "day \(target) from \(day)")
            }
        }
    }

    func testThisWeekendIsThisWeeksAndNeverNextWeeks() {
        for day in 20...26 {
            let bounds = range(.weekend, now: at(7, day, 15, 0))
            XCTAssertTrue(covers(bounds, at(7, 26)), "Sunday from day \(day)")
            XCTAssertEqual(covers(bounds, at(7, 25)), day <= 25, "Saturday from day \(day)")
            XCTAssertFalse(covers(bounds, at(8, 1)), "a week ahead from day \(day)")
        }
    }

    /// Sunday ends its week rather than starting the next, and the weekend
    /// it is already inside is today's — the old arithmetic jumped a week.
    func testSundayIsTheEndOfItsWeek() {
        let sunday = at(7, 26, 15, 0)
        XCTAssertTrue(covers(range(.week, now: sunday), at(7, 26)))
        XCTAssertTrue(covers(range(.nextweek, now: sunday), at(7, 27)))
        let weekend = range(.weekend, now: sunday)
        XCTAssertTrue(covers(weekend, at(7, 26)))
        XCTAssertFalse(covers(weekend, at(8, 1)))
        XCTAssertFalse(covers(weekend, at(8, 2)))
    }

    func testNoRangeEverStartsBeforeToday() {
        for day in 20...26 {
            let now = at(7, day, 15, 0)
            let midnight = instant(calendar.startOfDay(for: now))
            for preset in [EventDatePreset.weekend, .week, .month, .any] {
                XCTAssertGreaterThanOrEqual(range(preset, now: now).from, midnight, "\(preset.rawValue) on day \(day)")
            }
        }
    }

    /// A week whose Sunday is 23 or 25 hours long. Day arithmetic that adds
    /// 24-hour multiples drifts across these; calendar arithmetic does not.
    func testAWeekAcrossADaylightTransition() {
        for (month, sunday) in [(3, 8), (11, 1)] {
            let monday = at(month, sunday - 6, 15, 0)
            let bounds = range(.week, now: monday)
            for day in (sunday - 6)...sunday {
                XCTAssertTrue(covers(bounds, at(month, day)), "\(month)/\(day)")
            }
            XCTAssertTrue(covers(bounds, at(month, sunday, 23, 0)), "the transition day's evening")
            XCTAssertFalse(covers(bounds, at(month, sunday + 1, 0, 30)), "the Monday after")
        }
    }

    func testThisMonthRunsFromTodayToTheMonthsLastDay() {
        let bounds = range(.month, now: at(7, 23, 15, 30))
        XCTAssertTrue(covers(bounds, at(7, 23, 20)))
        XCTAssertTrue(covers(bounds, at(7, 31, 23, 30)))
        XCTAssertFalse(covers(bounds, at(8, 1)))
        XCTAssertFalse(covers(bounds, at(7, 22)))
        // February, where the last day is neither 30 nor 31.
        XCTAssertTrue(covers(range(.month, now: at(2, 3, 9)), at(2, 28, 21)))
        XCTAssertFalse(covers(range(.month, now: at(2, 3, 9)), at(3, 1)))
    }

    /// "Any date" still has a floor: the list calls itself upcoming, and the
    /// endpoint orders ascending with no default lower bound, so omitting
    /// `from` would serve a quilt's *oldest* events.
    func testAnyDateBoundsTheBottomAndNotTheTop() {
        let bounds = range(.any, now: at(7, 23, 15, 30))
        XCTAssertNil(bounds.to)
        XCTAssertEqual(bounds.from, instant(at(7, 23, 0, 0)))
    }

    /// The bounds are instants, never bare dates, and carry no fraction —
    /// `starts_at` holds two precisions and the comparison is text.
    func testBoundsAreWholeSecondInstants() {
        let bounds = range(.today, now: at(7, 23, 15, 30))
        XCTAssertTrue(bounds.from.hasSuffix("Z"), bounds.from)
        XCTAssertFalse(bounds.from.contains("."), bounds.from)
        XCTAssertFalse(bounds.to!.contains("."), bounds.to!)
        XCTAssertEqual(bounds.from.count, 20)
    }

    func testACustomRangeMayNameOneEndOrBoth() {
        let now = at(7, 23, 15, 30)
        let both = EventDateBounds.resolve(
            EventDateFilter(preset: .custom, customFrom: at(8, 1), customTo: at(8, 3)),
            now: now, timeZone: zone)
        XCTAssertTrue(covers(both, at(8, 3, 22)), "the last named day is inside its own range")
        XCTAssertFalse(covers(both, at(8, 4)))
        XCTAssertFalse(covers(both, at(7, 31, 23)))
        let open = EventDateBounds.resolve(
            EventDateFilter(preset: .custom, customFrom: at(8, 1), customTo: nil),
            now: now, timeZone: zone)
        XCTAssertNil(open.to)
        XCTAssertTrue(covers(open, at(12, 25)))
    }

    /// The zone is the quilt's, not the reader's: the same preset resolved
    /// in two zones names two different instants for the same word.
    func testTheQuiltsZoneDecidesWhereTheDayStarts() {
        let now = at(7, 23, 15, 30)
        let east = EventDateBounds.resolve(EventDateFilter(preset: .today), now: now, timeZone: zone)
        let utc = EventDateBounds.resolve(EventDateFilter(preset: .today), now: now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNotEqual(east.from, utc.from)
        XCTAssertEqual(east.from, "2026-07-23T04:00:00Z")
    }
}

/// The extended event, and the few decisions a row and a detail page make
/// from it.
final class EventModelTests: XCTestCase {
    private func decode(_ json: String) throws -> PatchworkEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PatchworkEvent.self, from: Data(json.utf8))
    }
    private let full = #"""
    {"id":"event","node_id":"node-1","title":"Open studio","description":"Bring something.",
     "location":"12 Example Street","latitude":40.0379,"longitude":-76.3055,
     "starts_at":"2026-09-26T18:00:00Z","ends_at":"2026-09-26T21:00:00Z","timezone":"America/New_York",
     "recurrence":"weekly","visibility":"members","status":"active","source_id":"feed-1",
     "image_url":"https://example.org/flyer.jpg","image_alt":"A flyer",
     "event_url":"https://www.tickets.example/show","node_name":"Common Thread","node_slug":"common-thread",
     "node_status":"unclaimed",
     "links":[{"id":"l1","node_id":"n2","node_name":"The Listening Room","node_slug":"listening-room","node_status":"active","status":"confirmed"},
              {"id":"l2","node_id":"n3","node_name":"Bike Kitchen","node_slug":"bike-kitchen","node_status":"active","status":"pending"}],
     "mentions":[{"id":"m1","host":"neighbor.example.org","slug":"paper-mill","name":"The Paper Mill"}]}
    """#

    func testTheExtendedEventDecodes() throws {
        let event = try decode(full)
        XCTAssertEqual(event.nodeId, "node-1")
        XCTAssertEqual(event.nodeStatus, "unclaimed")
        XCTAssertEqual(event.visibility, "members")
        XCTAssertEqual(event.recurrence, "weekly")
        XCTAssertEqual(event.sourceId, "feed-1")
        XCTAssertEqual(event.status, "active")
        XCTAssertEqual(event.latitude ?? 0, 40.0379, accuracy: 0.0001)
        XCTAssertEqual(event.longitude ?? 0, -76.3055, accuracy: 0.0001)
        XCTAssertEqual(event.imageAlt, "A flyer")
        XCTAssertNotNil(event.endDate)
    }

    /// Every added field is optional: a quilt on an older build sends a
    /// list row with none of them, and that is not an error.
    func testAThinRowStillDecodes() throws {
        let event = try decode(#"{"id":"e","title":"Gathering","starts_at":"2026-09-19T19:30:00Z"}"#)
        XCTAssertNil(event.visibility)
        XCTAssertNil(event.links)
        XCTAssertNil(event.latitude)
        XCTAssertFalse(event.communitySubmitted)
        XCTAssertNil(event.tierLabel)
        XCTAssertNil(event.recurrenceNote)
        XCTAssertTrue(event.confirmedLinks.isEmpty)
    }

    /// "with X" is a settled handshake. A pending one is invisible to
    /// everyone but the two sides, so it never becomes a chip.
    func testOnlyConfirmedLinksBecomeWithChips() throws {
        let event = try decode(full)
        XCTAssertEqual(event.links?.count, 2)
        XCTAssertEqual(event.confirmedLinks.map(\.nodeName), ["The Listening Room"])
        XCTAssertEqual(event.mentions?.first?.url?.absoluteString, "https://neighbor.example.org/patches/paper-mill")
        XCTAssertEqual(event.mentions?.first?.title, "The Paper Mill")
    }

    func testTheTierChipStaysAwayFromOrdinaryEvents() throws {
        XCTAssertNil(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-19T19:30:00Z","visibility":"public"}"#).tierLabel)
        XCTAssertEqual(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-19T19:30:00Z","visibility":"followers"}"#).tierLabel, "Followers")
        XCTAssertEqual(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-19T19:30:00Z","visibility":"members"}"#).tierLabel, "Members only")
    }

    func testARecurrenceWordIsToldTheTruth() throws {
        let event = try decode(full)
        XCTAssertEqual(event.recurrenceNote, "The organizer says this repeats weekly — only this date is on the calendar")
        // An empty string is what the API sends for "no recurrence".
        XCTAssertNil(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-19T19:30:00Z","recurrence":""}"#).recurrenceNote)
    }

    /// The day an event ends on is read in the event's own zone. Slicing the
    /// UTC string, which the web does, disagrees on either side of midnight —
    /// in both directions, and an ordinary Lancaster evening is one of them.
    func testTheSameDayTestUsesTheEventsOwnZone() throws {
        let overnight = try decode(#"{"id":"e","title":"Late set","starts_at":"2026-03-14T03:00:00Z","ends_at":"2026-03-14T05:00:00Z","timezone":"America/New_York"}"#)
        XCTAssertFalse(overnight.endsOnTheSameDay, "23:00 to 01:00 in New York is two days")
        let sameDay = try decode(full)
        XCTAssertTrue(sameDay.endsOnTheSameDay)
        // A real Lancaster listing: 7pm to 9pm on one Wednesday evening, which
        // straddles midnight in UTC. Comparing the stored strings calls this
        // two days and makes a two-hour quiz night read as an overnight.
        let trivia = try decode(#"{"id":"e","title":"Trivia Night","starts_at":"2026-09-23T23:00:00Z","ends_at":"2026-09-24T01:00:00Z","timezone":"America/New_York"}"#)
        XCTAssertNotEqual(String(trivia.startsAt.prefix(10)), String((trivia.endsAt ?? "").prefix(10)), "the stored days differ")
        XCTAssertTrue(trivia.endsOnTheSameDay, "but it is one evening where it happens")
        XCTAssertTrue(trivia.rangeLabel().hasPrefix(trivia.dateLabel), trivia.rangeLabel())
    }

    func testARangeReadsAsOneDateWhenItEndsOnThatDate() throws {
        let event = try decode(full)
        let label = event.rangeLabel()
        XCTAssertTrue(label.hasPrefix(event.dateLabel), label)
        XCTAssertTrue(label.contains("–"), label)
        // With no end there is nothing to join.
        let open = try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","timezone":"America/New_York"}"#)
        XCTAssertEqual(open.rangeLabel(), open.dateLabel)
    }

    func testOnlyBrowsableSchemesBecomeLinks() throws {
        XCTAssertEqual(try decode(full).externalURL?.host(), "www.tickets.example")
        XCTAssertNil(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","event_url":""}"#).externalURL)
        XCTAssertNil(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","event_url":"javascript:alert(1)"}"#).externalURL)
        XCTAssertNil(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","image_url":""}"#).flyerURL)
    }

    /// The calendar entry is built from the event's own fields rather than
    /// from the `.ics`, so this is where that mapping is pinned.
    func testTheCalendarEntryCarriesTheEventsFacts() throws {
        let event = try decode(full)
        let permalink = URL(string: "https://quilt.example.org/events/event")!
        let draft = try XCTUnwrap(CalendarDraft(event: event, permalink: permalink))
        XCTAssertEqual(draft.title, "Open studio")
        XCTAssertEqual(draft.start, event.date)
        XCTAssertEqual(draft.end, event.endDate)
        XCTAssertEqual(draft.location, "12 Example Street")
        XCTAssertEqual(draft.notes, "Bring something.")
        XCTAssertEqual(draft.url, permalink)
        XCTAssertEqual(draft.timeZone, TimeZone(identifier: "America/New_York"))
    }

    func testAnEventWithNoEndIsGivenAnHour() throws {
        let open = try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","location":"","description":""}"#)
        let draft = try XCTUnwrap(CalendarDraft(event: open, permalink: nil))
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), CalendarDraft.assumedLength)
        XCTAssertNil(draft.location, "an empty string is not a place")
        XCTAssertNil(draft.notes)
        XCTAssertNil(draft.timeZone)
    }

    /// An end before its own start is a feed's mistake, not a duration.
    func testAnInvertedRangeFallsBackToAnHour() throws {
        let inverted = try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","ends_at":"2026-09-26T17:00:00Z"}"#)
        let draft = try XCTUnwrap(CalendarDraft(event: inverted, permalink: nil))
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), CalendarDraft.assumedLength)
    }

    func testAnEventWithNoReadableStartHasNothingToAdd() throws {
        let broken = try decode(#"{"id":"e","title":"T","starts_at":"whenever"}"#)
        XCTAssertNil(CalendarDraft(event: broken, permalink: nil))
    }

    func testASubmissionAwaitingReviewSaysSo() throws {
        XCTAssertTrue(try decode(#"{"id":"e","title":"T","starts_at":"2026-09-26T18:00:00Z","status":"pending_review"}"#).awaitingReview)
        XCTAssertFalse(try decode(full).awaitingReview)
    }
}

/// The query the list actually sends.
final class EventQueryTests: XCTestCase {
    private let api = PatchworkAPI(base: URL(string: "https://quilt.example.org")!)

    func testAPatchsStandingFeedsAreTheQuiltsOwnEndpoints() {
        XCTAssertEqual(api.subscriptionURL(slug: "common-thread")?.absoluteString,
                       "webcal://quilt.example.org/api/v1/nodes/common-thread/events.ics")
        XCTAssertEqual(api.feedURL(slug: "common-thread").absoluteString,
                       "https://quilt.example.org/api/v1/nodes/common-thread/events.rss")
    }
}
