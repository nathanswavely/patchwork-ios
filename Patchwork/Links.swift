// SPDX-License-Identifier: MPL-2.0

import SafariServices
import SwiftUI
import UIKit

/// Where a link to a quilt's website lands in this app.
///
/// A quilt whose admin lets its links open in the app (web ADR of
/// 2026-10-18) names in its association file the paths this client shows
/// natively, and iOS hands a tap on one of them here instead of to Safari.
/// The website's own route table is the vocabulary: most paths are the
/// notifications' (`NotificationLink`), and the rest are the shell's — a tab,
/// a page of the quilt's information stack, the bell, an account invite.
enum LinkTarget: Equatable {
    case quilt(my: Bool)
    case events(my: Bool)
    case discover
    case dashboard
    case notifications
    case info(InfoPage)
    /// An account invite link, carried whole: the invite sheet reads its token.
    case invite(link: String)
    case patch(slug: String)
    case screen(NotificationLink.Destination)
    /// A path the app has not built, opened on the website inside the app.
    case website(path: String)

    static func of(_ url: URL) -> LinkTarget {
        let path = url.path(percentEncoded: true)
        let parts = path.split(separator: "/").map(String.init)
        if parts.count == 2, parts[0] == "invite" { return .invite(link: url.absoluteString) }
        switch parts {
        case [], ["patches"], ["map"]: return .quilt(my: false)
        case ["my"], ["map", "my"]: return .quilt(my: true)
        case ["events"]: return .events(my: false)
        case ["events", "my"]: return .events(my: true)
        case ["discover"]: return .discover
        case ["dashboard"]: return .dashboard
        case ["notifications"]: return .notifications
        case ["about"]: return .info(.about)
        case ["label"]: return .info(.label)
        case ["lining"]: return .info(.lining)
        case ["governance"]: return .info(.governance)
        case ["privacy"]: return .info(.privacy)
        case ["terms"]: return .info(.terms)
        // Two forms whose names would otherwise read as an id.
        case ["patches", "new"], ["events", "new"]: return .website(path: path)
        default: break
        }
        let whole = path + (url.query(percentEncoded: true).map { "?" + $0 } ?? "")
        switch NotificationLink.route(whole) {
        case .patch(let slug): return .patch(slug: slug)
        case .website(let rest): return .website(path: rest)
        case let destination: return .screen(destination)
        }
    }
}

/// What a link opens over the quilt, when it is more than a tab or a patch.
enum LinkedSheet: Identifiable {
    case screen(NotificationLink.Destination)
    case info(InfoPage)
    case invite(link: String)
    case notifications
    case website(URL)
    var id: String {
        switch self {
        case .screen(let destination): return "screen-\(destination)"
        case .info(let page): return "info-\(page)"
        case .invite(let link): return "invite-\(link)"
        case .notifications: return "notifications"
        case .website(let url): return "website-\(url)"
        }
    }
}

struct LinkedSheetView: View {
    let sheet: LinkedSheet
    var body: some View {
        switch sheet {
        case .screen(let destination): LinkedScreen(destination: destination)
        case .info(let page): NavigationStack { page.view.modifier(SheetDone()) }
        case .invite(let link): InviteSheet(link: link)
        case .notifications: NotificationsSheet()
        case .website(let url): InAppSafari(url: url).ignoresSafeArea()
        }
    }
}

/// One linked screen in a sheet of its own, fetched before it is drawn the
/// way a notification's is, with the website inside the app as the way out
/// when it cannot be.
private struct LinkedScreen: View {
    let destination: NotificationLink.Destination
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var route: NotificationRoute?
    @State private var failure: String?
    @State private var browsing: URL?
    var body: some View {
        NavigationStack {
            Group {
                if let route {
                    RouteScreen(route: route) { dismiss() }
                } else if let failure {
                    ContentUnavailableView {
                        Label("Couldn’t open this link", systemImage: "link")
                    } description: {
                        Text(failure).font(Font.pw.subheadline)
                    } actions: {
                        Button("Open on the website") { browsing = webURL }
                            .font(Font.pw.headline)
                            .accessibilityIdentifier("linkOpenWebsite")
                    }
                    .accessibilityIdentifier("linkFailed")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pwGround.ignoresSafeArea())
            .modifier(SheetDone())
        }
        .sheet(item: $browsing) { InAppSafari(url: $0).ignoresSafeArea() }
        .task { await resolve() }
    }
    private var webURL: URL {
        if case .website(let path) = destination {
            let exit = NotificationLink.exit(path)
            return session.api.webURL(exit.path, query: exit.query)
        }
        return session.quilt.url
    }
    private func resolve() async {
        do { route = try await destination.screen(in: session) }
        catch APIError.unauthenticated {
            session.signedOut()
            failure = "Sign in to \(session.instance?.name ?? session.quilt.name) to see this."
        } catch {
            failure = "It may have been removed, or the quilt could not be reached just now."
        }
    }
}

/// The website inside the app. A link this app has claimed would come
/// straight back here if it were handed to the system, so a page the app has
/// not built opens in Safari's own view instead.
struct InAppSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.pwAccent)
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Clears whatever is presented over the quilt so a link's own screen can
/// take its place. A sheet that may not be let go of — recovery codes on
/// screen, a form mid-send — keeps the link from interrupting it.
@MainActor enum Presentations {
    static func clear() async -> Bool {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return true }
        var top = root.presentedViewController
        var held = false
        while let presented = top {
            if presented.isModalInPresentation { held = true }
            top = presented.presentedViewController
        }
        guard !held else { return false }
        guard root.presentedViewController != nil else { return true }
        root.dismiss(animated: true)
        try? await Task.sleep(for: .milliseconds(600))
        return true
    }
}
