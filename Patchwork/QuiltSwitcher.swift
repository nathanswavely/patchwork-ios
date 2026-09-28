// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// What holding the Quilt tab opens: a small card, the way holding a profile
/// tab offers accounts rather than a sign-in page. It answers the two
/// questions a hold asks — which lens am I reading this quilt through, and
/// which other quilt could I be on — and leaves finding a new quilt to the
/// full picker behind one button.
///
/// Scope is the web's (ADR 022, 035): the whole quilt is the unmarked default
/// and the one every launch starts on; My Quilt is offered only to somebody
/// the quilt knows, because it is the server's answer about an account.
struct QuiltSwitcher: View {
    @EnvironmentObject private var session: QuiltSession
    @EnvironmentObject private var store: QuiltStore
    @Environment(\.dismiss) private var dismiss
    /// Hands the reader on to the full picker. The card closes first and the
    /// picker opens as its own sheet, so its Done, its search and its
    /// inspect-and-confirm behave exactly as they do everywhere else.
    let findQuilt: () -> Void
    /// Saved quilts other than this one. They were inspected and confirmed
    /// when first saved, so a tap connects rather than asking again.
    private var others: [Quilt] { store.saved.filter { $0.id != session.quilt.id } }
    private var quiltName: String { session.instance?.name ?? session.quilt.name }
    var body: some View {
        NavigationStack {
            List {
                // One Group so every section's rows take the card surface.
                Group {
                    Section {
                        scopeRow(.whole, title: quiltName, detail: "Every patch on this quilt", id: "scopeWhole")
                        if session.me != nil {
                            scopeRow(.my, title: "My Quilt", detail: "The patches you follow or join", id: "scopeMy")
                        } else {
                            // No stub: signing in is the account menu's, and
                            // this line only says what it would bring.
                            Text("Sign in to see the patches you follow as a quilt of their own.")
                                .font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("scopeSignedOut")
                        }
                    } header: { heading("This quilt") }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { quilt in
                                Button { dismiss(); store.connect(quilt) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(quilt.name).font(Font.pw.headline).foregroundStyle(Color.pwText)
                                            Text(quilt.url.host() ?? quilt.id).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("switchQuilt")
                            }
                        } header: { heading("Other quilts") }
                    }
                    Section {
                        Button { findQuilt() } label: {
                            Label("Find a quilt", systemImage: "magnifyingglass").font(Font.pw.subheadlineMedium)
                        }
                        .buttonStyle(.plain)
                        .inkRow()
                        .accessibilityIdentifier("findQuilt")
                    }
                }.listRows()
            }
            .groundedList()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quiltSwitcher")
            .navigationTitle("Switch quilt").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    /// One lens: its name, one line about what it holds, and a checkmark on
    /// the one in use. Choosing closes the card; the quilt behind it is
    /// already redrawing under the new lens.
    private func scopeRow(_ scope: QuiltScope, title: String, detail: String, id: String) -> some View {
        Button { session.scope = scope; dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                    Text(detail).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                }
                Spacer()
                if session.scope == scope {
                    // The checkmark is the one mark of selection here, and
                    // selection is what the tint means.
                    Image(systemName: "checkmark").font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(session.scope == scope ? .isSelected : [])
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
    }
}
