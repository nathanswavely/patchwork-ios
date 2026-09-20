// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The filter's control and indicator as one thing: every tag this quilt
/// wears, most-worn first, with the search chip among them. Open while in
/// use — the quilt repacks behind it as chips toggle.
struct FilterSheet: View {
    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    private var query: String { session.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(session.filtered.count) of \(session.patches.count) patches").font(.subheadline).foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        if !query.isEmpty {
                            Chip(title: "“\(query)”", active: true, trailing: "xmark") { session.query = "" }
                                .accessibilityLabel("Showing matches for \(query)").accessibilityHint("Clears the search")
                        }
                        ForEach(session.rankedTags, id: \.tag) { entry in
                            Chip(title: entry.tag, active: session.tags.contains(entry.tag)) {
                                if session.tags.contains(entry.tag) { session.tags.remove(entry.tag) } else { session.tags.insert(entry.tag) }
                            }
                        }
                    }
                    if session.rankedTags.isEmpty { Text("This quilt hasn’t tagged its patches yet.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("Filter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Clear") { session.clearFilters() }.disabled(session.activeFilterCount == 0) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

struct Chip: View {
    let title: String
    var count: Int? = nil
    let active: Bool
    var trailing: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Group {
            if active {
                Button(action: action) { label }.buttonStyle(.borderedProminent)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            } else {
                Button(action: action) { label }.buttonStyle(.bordered).tint(.gray).foregroundStyle(Color.primary)
            }
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel(title)
        .accessibilityValue(count.map { "\($0) patch\($0 == 1 ? "" : "es")" } ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    private var label: some View {
        HStack(spacing: 5) {
            if active && trailing == nil { Image(systemName: "checkmark").font(.caption.bold()) }
            Text(title)
            if let count { Text("\(count)").font(.caption).opacity(0.75) }
            if let trailing { Image(systemName: trailing).font(.caption.bold()) }
        }.font(.subheadline.weight(.medium)).lineLimit(1)
    }
}

/// Rows of chips that wrap at the container's width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placed = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? placed.width, height: placed.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(bounds.width, subviews)
        for (index, origin) in placed.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + row)
    }
}
