// SPDX-License-Identifier: MPL-2.0

import EventKit
import EventKitUI
import SwiftUI
import UIKit

/// One night, in your own calendar. Patchwork tells nobody an event is
/// coming, so this and subscribing to a patch are the whole of how a
/// calendar reaches a person who asked for it.
///
/// The entry is built from the event's own fields rather than by parsing the
/// quilt's `.ics` — EventKit wants a start, an end, a zone and a place, and
/// the JSON already says all four in the precision they are stored at. The
/// `.ics` is still fetched, unparsed, for the share fallback: a person who
/// keeps their calendar somewhere other than iOS gets the file the web
/// hands them, byte for byte.
struct CalendarDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var notes: String?
    var url: URL?
    var timeZone: TimeZone?
    /// What an event with no stated end is worth on a calendar. An entry
    /// with zero length reads as a moment rather than a gathering.
    static let assumedLength: TimeInterval = 3600

    init?(event: PatchworkEvent, permalink: URL?) {
        guard let start = event.date else { return nil }
        // An end before its own start is a feed's mistake, not a duration.
        let stated = event.endDate.flatMap { $0 > start ? $0 : nil }
        self.title = event.title
        self.start = start
        self.end = stated ?? start.addingTimeInterval(Self.assumedLength)
        self.location = event.location?.isEmpty == false ? event.location : nil
        self.notes = event.description?.isEmpty == false ? event.description : nil
        self.url = permalink
        self.timeZone = event.timezone.flatMap { TimeZone(identifier: $0) }
    }

    func apply(to entry: EKEvent) -> EKEvent {
        entry.title = title
        entry.startDate = start
        entry.endDate = end
        entry.location = location
        entry.notes = notes
        entry.url = url
        if let timeZone { entry.timeZone = timeZone }
        return entry
    }
}

/// The affordance itself: a menu, so opening it commits to nothing and the
/// calendar is only asked for once the choice is made.
struct AddToCalendarMenu: View {
    let event: PatchworkEvent
    let permalink: URL
    let api: PatchworkAPI
    @State private var store = EKEventStore()
    @State private var draft: CalendarDraft?
    @State private var file: SharedFile?
    @State private var denied = false
    @State private var failure: String?

    var body: some View {
        Menu {
            Button { Task { await addToCalendar() } } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                .accessibilityIdentifier("addToCalendar")
            Button { Task { await shareFile() } } label: { Label("Share calendar file", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("shareCalendarFile")
        } label: {
            Label("Add to calendar", systemImage: "calendar.badge.plus")
        }
        .accessibilityIdentifier("addToCalendarMenu")
        .sheet(item: $draft) { draft in
            EventEditSheet(store: store, draft: draft) { self.draft = nil }
                .ignoresSafeArea()
        }
        .sheet(item: $file) { file in ActivitySheet(url: file.url).ignoresSafeArea() }
        .alert("Patchwork can’t reach your calendar", isPresented: $denied) {
            Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Calendar access is off for Patchwork. You can still share the event’s calendar file instead.")
        }
        .alert("That didn’t work", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func addToCalendar() async {
        guard let draft = CalendarDraft(event: event, permalink: permalink) else {
            failure = "This event doesn’t say when it starts."
            return
        }
        let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        if granted { self.draft = draft } else { denied = true }
    }

    private func shareFile() async {
        do {
            let data = try await api.eventCalendar(event.id)
            let name = event.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.prefix(6).joined(separator: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.isEmpty ? "event" : name)
                .appendingPathExtension("ics")
            try data.write(to: url, options: .atomic)
            file = SharedFile(url: url)
        } catch {
            failure = "The quilt did not hand over this event’s calendar file."
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension CalendarDraft: Identifiable {
    var id: String { "\(title)-\(start.timeIntervalSince1970)" }
}

/// The system's own event editor, so the calendar, the alert and the invitees
/// are chosen where a person already knows how to choose them.
struct EventEditSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let draft: CalendarDraft
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = draft.apply(to: EKEvent(eventStore: store))
        controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDismiss()
        }
    }
}

/// The share sheet, for the `.ics` fallback.
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
