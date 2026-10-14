// SPDX-License-Identifier: MPL-2.0

import MapKit
import SwiftUI

// The web's `/patches/new` (PatchForm.svelte), natively: the fork question
// first, then one form in the step pattern — the fields in the web's order,
// the act at the foot. The same form is a claim's setup (ADR 039), filled
// from the listing. Drafting a block of one's own, picking fabrics for a
// bundle, previewing a template's rules and the two exposure switches are
// Patch Settings' on the website.

// MARK: - The sheet

/// "Add a patch": the fork, then the form or the suggestion. One sheet, its
/// content swapped, because the fork is a question about this visit and not
/// a place anybody goes back to.
struct NewPatchSheet: View {
    enum Start: Equatable {
        /// The fork: "Is this your patch to run?"
        case fork
        /// Straight to the suggestion form, carrying a name already typed.
        case suggest(name: String)
    }
    private enum Phase: Equatable { case fork, create, suggest(String) }

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase

    init(start: Start = .fork) {
        switch start {
        case .fork: _phase = State(initialValue: .fork)
        case .suggest(let name): _phase = State(initialValue: .suggest(name))
        }
    }

    var body: some View {
        NavigationStack {
            switch phase {
            case .fork: fork
            case .create:
                PatchFormView(mode: .create, draft: PatchDraft.seeded(),
                              suggestInstead: session.instance?.submissionsEnabled == true ? { phase = .suggest("") } : nil)
            case .suggest(let name):
                SuggestPatchForm(name: name)
            }
        }
        // Signed out from under it — a 401 anywhere — there is nobody left
        // to make a patch as.
        .onChange(of: session.me == nil) { _, gone in if gone { dismiss() } }
    }

    /// The fork (web ADR 2026-09-18): asked before any field, so nothing
    /// promises admin of a place nobody has admitted the reader to.
    private var fork: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add a patch")
                    .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("addPatchHeading")
                Text("Is this your patch to run?")
                    .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                forkCard(title: "I run this patch",
                         detail: "You become its admin. Members, events and settings are yours from the start.",
                         symbol: "wrench.and.screwdriver", identifier: "forkRun") { withAnimation { phase = .create } }
                if session.instance?.submissionsEnabled != false {
                    forkCard(title: "Someone else runs it",
                             detail: "It joins the quilt as an unclaimed patch. The people who run it can claim it later, and you can add its events once it's approved.",
                             symbol: "person.2", identifier: "forkSuggest") { withAnimation { phase = .suggest("") } }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func forkCard(title: String, detail: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(Font.pw.headline).foregroundStyle(Color.pwTextMuted)
                    .frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Font.pw.headline).foregroundStyle(Color.pwText)
                    Text(detail).font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.pwTextMuted)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The Dashboard's "Add a patch", the web's quick action: one ink row on a
/// card, opening the fork.
struct AddPatchDoor: View {
    @EnvironmentObject private var session: QuiltSession
    @State private var adding = false
    var body: some View {
        Button { adding = true } label: {
            Text("Add a patch").font(Font.pw.subheadlineSemibold).inkAction("plus.square")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboardAddPatch")
        .sheet(isPresented: $adding, onDismiss: { session.sheetDismissed() }) { NewPatchSheet() }
    }
}

// MARK: - The form

/// Create or set up. Creation sends `POST nodes`; setup sends the claim's
/// `setup` and then `PATCH nodes/{slug}`, as the web does.
struct PatchFormView: View {
    enum Mode: Equatable {
        case create
        /// The claim being spent, the patch's address, and when the right
        /// to set it up runs out.
        case setup(claimID: String, slug: String, expiresAt: String?)
    }
    let mode: Mode
    var suggestInstead: (() -> Void)? = nil
    /// Setup's ending, for a presenter that has a patch to show; creation
    /// docks the new patch on the quilt itself.
    var onFinished: (String) -> Void = { _ in }

    @EnvironmentObject private var session: QuiltSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PatchDraft
    @State private var busy = false
    @State private var failure: String?
    /// A setup the quilt refused for good — the window closed, or somebody
    /// else's claim got there first. The form stays to be read; the act at
    /// its foot becomes the way out.
    @State private var finished = false
    // The map: whether the picker is up, the suggestion it opened on, and
    // whether a lookup is out.
    @State private var picking = false
    @State private var suggestion: PlaceSuggestion?
    @State private var lookingUp = false
    @State private var lastLookedUp = ""
    @FocusState private var addressFocused: Bool

    init(mode: Mode, draft: PatchDraft, suggestInstead: (() -> Void)? = nil, onFinished: @escaping (String) -> Void = { _ in }) {
        self.mode = mode
        self.suggestInstead = suggestInstead
        self.onFinished = onFinished
        _draft = State(initialValue: draft)
    }

    private var setup: Bool { if case .setup = mode { return true } else { return false } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { form }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.pwGround.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        .safeAreaInset(edge: .bottom) { foot }
        .interactiveDismissDisabled(busy)
    }

    // MARK: Fields, in the web's order

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(setup ? "Set up your patch" : "Create Patch")
                .font(Font.pw.displayTitle2).foregroundStyle(Color.pwText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("patchFormHeading")
            Text(setup ? "Complete this patch's details to activate it." : "Start a new community, collective, venue, or group.")
                .font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            if case .setup(_, _, let expiresAt) = mode, let day = MyPatchesRules.day(expiresAt) {
                Text("Approval expires \(day).").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("setupExpires")
            }
            if let suggestInstead {
                Button(action: suggestInstead) {
                    Text("Not yours to run? Suggest it instead").font(Font.pw.subheadline)
                }
                .buttonStyle(.plain)
                .inkAction("arrow.uturn.right")
                .padding(.top, 4)
                .accessibilityIdentifier("suggestInstead")
            }
        }
        if case .setup(_, let slug, _) = mode {
            field("Address", hint: "This is the patch's existing address.") {
                Text(verbatim: slug).font(Font.pw.body).foregroundStyle(Color.pwTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldStyle()
                    .accessibilityIdentifier("setupSlug")
            }
        }
        field("Name", required: true) {
            TextField("e.g. Gallery Row, Lancaster Beats Lab", text: $draft.name)
                .textInputAutocapitalization(.words)
                .fieldStyle()
                .accessibilityIdentifier("patchName")
        }
        field("Description") {
            TextField("What is this patch about?", text: $draft.description, axis: .vertical)
                .lineLimit(3...8)
                .fieldStyle()
                .accessibilityIdentifier("patchDescription")
        }
        addressField
        field("Website") {
            TextField(text: $draft.website, prompt: Text(verbatim: "https://...")) { Text("Website") }
                .keyboardType(.URL).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .fieldStyle()
                .accessibilityIdentifier("patchWebsite")
        }
        field("Tags", hint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What kind of patch is this? Tags help people find you, and new patches are placed near others with the same tags on the quilt. The first tag decides your default motif. Missing a word? Suggest it, and an admin decides whether it joins the quilt's tags.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                TagPicker(picked: $draft.tags, suggested: $draft.suggestTags, vocabulary: session.tagTerms, allowSuggesting: true)
            }
        }
        AppearancePicker(draft: $draft, tagMotifs: session.tagMotifs)
        lining
        field("Members and governance") {
            Text("Your member list and your proposals start out visible to members only. Events, your description and your tile are public. You can publish either one later in Patch Settings.")
                .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        policyField
        templateField
        if let failure {
            Label { Text(failure).font(Font.pw.footnote) } icon: {
                Image(systemName: "exclamationmark.circle").font(Font.pw.footnote)
            }
            .foregroundStyle(Color.pwText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("patchFormError")
        }
    }

    // MARK: The address and its point

    /// The address and the map stay separate acts (web ADR 082): leaving the
    /// field may propose a point, and nothing is sent unless somebody
    /// confirms one on the map.
    private var addressField: some View {
        field("Address") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Where is this based?", text: $draft.address)
                    .textContentType(.fullStreetAddress)
                    .focused($addressFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await addressSettled() } }
                    .fieldStyle()
                    .accessibilityIdentifier("patchAddress")
                    .onChange(of: addressFocused) { was, now in if was && !now { Task { await addressSettled() } } }
                if let point = draft.point {
                    HStack(spacing: 10) {
                        Label("On the map.", systemImage: "mappin.circle")
                            .font(Font.pw.subheadline).foregroundStyle(Color.pwText)
                            .accessibilityIdentifier("placedOnMap")
                        Button("Remove") { withAnimation { draft.point = nil; picking = false; suggestion = nil } }
                            .font(Font.pw.subheadlineSemibold)
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.pwText)
                            .underline()
                            .accessibilityIdentifier("removePlacement")
                    }
                    .accessibilityValue(PlacePicker.readout(point))
                } else if lookingUp {
                    Text("Looking for this address...").font(Font.pw.subheadline).foregroundStyle(Color.pwTextMuted)
                } else if picking {
                    PlacePicker(seed: suggestion?.point ?? fallbackCenter,
                                provisional: suggestion?.point != nil,
                                label: suggestion?.label) { point in
                        withAnimation { draft.point = point; picking = false; suggestion = nil }
                    } onCancel: {
                        withAnimation { picking = false; suggestion = nil }
                    }
                } else {
                    Button { withAnimation { picking = true } } label: {
                        Text("Put it on the map").font(Font.pw.subheadline)
                    }
                    .buttonStyle(.plain)
                    .inkAction("mappin.and.ellipse")
                    .accessibilityIdentifier("putOnMap")
                }
            }
        }
    }

    /// Where the map opens when the address proposes nothing: the quilt's
    /// own centre, else the middle of the patches it has placed.
    private var fallbackCenter: MapPoint? {
        if let latitude = session.instance?.geography.latitude, let longitude = session.instance?.geography.longitude,
           latitude != 0 || longitude != 0 {
            return MapPoint(latitude: latitude, longitude: longitude)
        }
        let placed = session.wholeQuilt.filter(\.isPlaced)
        guard !placed.isEmpty else { return nil }
        return MapPoint(latitude: placed.map { $0.latitude ?? 0 }.reduce(0, +) / Double(placed.count),
                        longitude: placed.map { $0.longitude ?? 0 }.reduce(0, +) / Double(placed.count))
    }

    /// Fired when the field is left, never per keystroke: a map that
    /// appears mid-typing moves every control under the person's thumb.
    private func addressSettled() async {
        let query = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceSuggestion.worthLookingUp(query), query != lastLookedUp else { return }
        lastLookedUp = query
        // A point the person already placed is theirs; never propose over it.
        guard draft.point == nil else { return }
        lookingUp = true
        suggestion = await session.api.suggestPlace(query)
        lookingUp = false
        withAnimation { picking = true }
    }

    // MARK: The lining

    private var lining: some View {
        field("The lining") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every patch starts with a shared community standards called the lining. It is always public, and if your patch amends it, the changes are public and the patch is marked as having amended the lining.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink { LiningView() } label: {
                    Text("Read the lining").font(Font.pw.subheadline).inkRow(fills: false)
                }
                .accessibilityIdentifier("readLining")
            }
        }
    }

    // MARK: Policy and template

    private var policyField: some View {
        field("Membership Policy", required: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Members vote on proposals and appear in the patch's member list. Following is separate and always open: anyone can follow a public patch and see its events.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if setup && !draft.policyAnswered {
                    // What the control cannot show: this answer came from the
                    // template below and will keep following it until it is
                    // answered here.
                    Text("Set by the \(draft.template.name) template. Change it if that is not this patch.")
                        .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                        .accessibilityIdentifier("policySeeded")
                }
                ForEach(MembershipPolicyChoice.allCases) { choice in
                    ChoiceCard(title: choice.name, detail: choice.detail, selected: draft.policy == choice,
                               identifier: "policy-\(choice.rawValue)") { draft.answer(choice) }
                }
            }
        }
    }

    private var templateField: some View {
        field("Governance Template") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How should this patch be organized? You can change this later.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                ForEach(GovernanceTemplate.allCases) { template in
                    ChoiceCard(title: template.name, detail: template.detail,
                               meta: "\(template.leadership) · \(template.bestFor)",
                               selected: draft.template == template,
                               identifier: "template-\(template.rawValue)") { draft.choose(template, setup: setup) }
                }
            }
        }
    }

    private func field<Content: View>(_ title: String, required: Bool = false, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                if required { Text("*").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted).accessibilityLabel("required") }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
            if let hint {
                Text(hint).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The act

    private var foot: some View {
        Button { if finished { dismiss() } else { submit() } } label: {
            Group {
                if busy { ProgressView().tint(.white) }
                else { Text(finished ? "Done" : (setup ? "Finish setup" : "Create Patch")).font(Font.pw.headline) }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(busy ? Color.pwTextMuted : Color.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.pwAccent)
        .controlSize(.large)
        .disabled(busy)
        .accessibilityIdentifier("patchFormSubmit")
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        guard !busy else { return }
        failure = nil
        if let problem = draft.problem() { failure = problem; return }
        busy = true
        Task {
            defer { busy = false }
            switch mode {
            case .create: await create()
            case .setup(let claimID, let slug, _): await finishSetup(claimID: claimID, slug: slug)
            }
        }
    }

    /// `POST nodes`, then the index and the quilt read again so the new
    /// patch is there to dock, and docked once this sheet has gone.
    private func create() async {
        do {
            let created = try await session.api.createPatch(draft.createBody)
            await session.refreshMemberships()
            await session.loadTree(refreshingWhole: true)
            let slug = created.node.slug
            // A word an admin already declined does not fail the creation;
            // the patch exists, and the reader is told why the chip is gone.
            let warning = created.tagWarning.map { " " + sentenceCased($0) } ?? ""
            session.arrival = ArrivalNote(slug: slug, text: "Patch created." + warning)
            session.dock(afterSheet: slug)
            dismiss()
        } catch APIError.unauthenticated {
            session.signedOut()
        } catch {
            failure = sentenceCased(ProposalDetailView.sentence(error, fallback: "Failed to create patch"))
        }
    }

    /// The claim's setup, then the fields. A refusal of the first is the
    /// server's sentence; a failure of the second is not fatal — the patch
    /// is the claimant's already and the edits wait in Patch Settings.
    private func finishSetup(claimID: String, slug: String) async {
        do {
            try await session.api.sendVoid("POST", "claims/\(claimID)/setup", body: draft.setupBody)
        } catch APIError.unauthenticated {
            session.signedOut()
            return
        } catch {
            failure = PatchSetupRules.sentence(error)
            finished = PatchSetupRules.isFinal(error)
            return
        }
        var note = "This patch is yours"
        do { try await session.api.sendVoid("PATCH", "nodes/\(slug)", body: draft.updateBody) }
        catch { note = "Patch set up. Finish edits in Patch Settings." }
        await session.refreshMemberships()
        await session.loadTree(refreshingWhole: true)
        session.arrival = ArrivalNote(slug: slug, text: note)
        onFinished(slug)
        dismiss()
    }
}

/// How a setup's refusal is said (web PatchForm.svelte): the window that
/// closed in the server's own sentence, somebody else's setup in the web's,
/// and anything else as the server put it.
enum PatchSetupRules {
    static let noLongerClaimable = "This patch is no longer claimable."
    static func sentence(_ error: Error) -> String {
        if let status = (error as? APIError)?.httpStatus {
            if status == 409 { return noLongerClaimable }
            if status == 410 { return sentenceCased(SignInModel.sentence(error)) }
        }
        return sentenceCased(ProposalDetailView.sentence(error, fallback: "Failed to complete setup"))
    }
    /// A closed window or a patch somebody else set up: no second press of
    /// the same button will do anything.
    static func isFinal(_ error: Error) -> Bool { [409, 410].contains((error as? APIError)?.httpStatus ?? 0) }
}

// MARK: - A radio card

/// One of a set, as the web's policy and template cards are: the title, what
/// it means, and the state as a filled circle in the tint — a control, so
/// the tint belongs on it.
struct ChoiceCard: View {
    let title: String
    let detail: String
    var meta: String? = nil
    let selected: Bool
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(Font.pw.body)
                    .foregroundStyle(selected ? Color.pwAccent : Color.pwTextMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Font.pw.subheadlineSemibold).foregroundStyle(Color.pwText)
                    Text(detail).font(Font.pw.footnote).foregroundStyle(Color.pwTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta).font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .contentShape(Rectangle())
            .background(Color.pwSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Color.pwAccent : Color.pwBorder, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - The map

/// The web's map location picker, natively: the map moves under a fixed pin,
/// and the point is the pin's — the platform's own way of placing something
/// precisely with a thumb. Nothing is placed until the button is pressed.
struct PlacePicker: View {
    let seed: MapPoint?
    /// The seed is the gazetteer's guess rather than a point anybody placed.
    let provisional: Bool
    let label: String?
    let onSave: (MapPoint) -> Void
    let onCancel: () -> Void

    @State private var position: MapCameraPosition
    @State private var center: MapPoint?

    init(seed: MapPoint?, provisional: Bool, label: String?, onSave: @escaping (MapPoint) -> Void, onCancel: @escaping () -> Void) {
        self.seed = seed; self.provisional = provisional; self.label = label
        self.onSave = onSave; self.onCancel = onCancel
        let coordinate = CLLocationCoordinate2D(latitude: seed?.latitude ?? 20, longitude: seed?.longitude ?? 0)
        let span = seed == nil ? MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120) : MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        _position = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
        _center = State(initialValue: seed)
    }

    static func readout(_ point: MapPoint) -> String {
        String(format: "%.5f, %.5f", point.latitude, point.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provisional, let label, !label.isEmpty {
                Text("Suggested from the address: \(label)")
                    .font(Font.pw.footnote).foregroundStyle(Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("placeSuggestion")
            }
            Map(position: $position, interactionModes: [.pan, .zoom])
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = MapPoint(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                }
                .overlay {
                    // The pin's tip is the point: lifted by half its height so
                    // the tip, not the head, sits on the map's centre.
                    Image(systemName: "mappin")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.pwAccent)
                        .offset(y: -15)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: FieldStyle.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FieldStyle.radius, style: .continuous).strokeBorder(Color.pwBorder, lineWidth: 1))
                .accessibilityLabel("Map")
                .accessibilityIdentifier("placeMap")
            Text(provisional
                 ? "This is a guess, not a placement. Move the map to put the pin where it belongs, and nothing goes on the map until you confirm."
                 : "Move the map to put the pin where this patch is, as precisely or as loosely as you like. Nothing is saved until you choose Save location.")
                .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let center {
                Text(Self.readout(center)).font(.caption.monospaced()).foregroundStyle(Color.pwTextMuted)
                    .accessibilityIdentifier("placeReadout")
            } else {
                Text("No marker placed yet.").font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            HStack(spacing: 12) {
                Button { if let center, center.isValid { onSave(center) } } label: {
                    Text(provisional ? "Use this spot" : "Save location").font(Font.pw.subheadlineSemibold)
                        .foregroundStyle(center == nil ? Color.pwTextMuted : Color.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pwAccent)
                .disabled(center == nil)
                .accessibilityIdentifier("savePlacement")
                Button("Cancel", action: onCancel)
                    .font(Font.pw.subheadline)
                    .buttonStyle(.bordered)
                    .tint(Color.pwText)
                    .accessibilityIdentifier("cancelPlacement")
            }
        }
    }
}

// MARK: - Tags

/// The web's tag picker: the picked tags in priority order, the words
/// waiting to be suggested, and the rest of the vocabulary to pick from —
/// chips in the filter sheet's flow — then a field to suggest a word that
/// is missing.
struct TagPicker: View {
    @Binding var picked: [String]
    @Binding var suggested: [String]
    let vocabulary: [TagTerm]
    /// A suggestion of a patch carries curated tags only.
    let allowSuggesting: Bool
    @State private var word = ""
    @State private var refusal: String?

    private var available: [TagTerm] { vocabulary.filter { !picked.contains($0.name) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !picked.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(picked.enumerated()), id: \.element) { index, name in
                        chip(name, symbol: "xmark", filled: true, label: "Remove \(name)") { picked.remove(at: index) }
                            .accessibilityIdentifier("pickedTag-\(name)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Selected tags, in priority order")
            }
            if !suggested.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggested, id: \.self) { name in
                        chip("\(name) · to suggest", symbol: "xmark", filled: false, dashed: true, label: "Remove \(name)") {
                            suggested.removeAll { $0 == name }
                        }
                        .accessibilityIdentifier("suggestedTag-\(name)")
                    }
                }
            }
            if !available.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(available, id: \.name) { term in
                        chip(term.name, symbol: "plus", filled: false, label: "Add \(term.name)") { picked.append(term.name) }
                            .accessibilityIdentifier("tagChoice-\(term.name)")
                    }
                }
            } else if vocabulary.isEmpty {
                Text("No tags yet. The instance admin curates the list.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
            }
            if allowSuggesting {
                HStack(spacing: 8) {
                    TextField("Suggest a tag", text: $word)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(suggest)
                        .onChange(of: word) { _, now in if now.count > 32 { word = String(now.prefix(32)) }; refusal = nil }
                        .fieldStyle()
                        .accessibilityLabel("Suggest a tag that is not on the list")
                        .accessibilityIdentifier("suggestTagField")
                    Button(action: suggest) { Label("Suggest", systemImage: "plus").font(Font.pw.subheadlineSemibold) }
                        .buttonStyle(.bordered)
                        .tint(Color.pwText)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("suggestTag")
                }
                Text(refusal ?? "A suggested tag stays on this patch privately until an admin adds it to the quilt's tags.")
                    .font(Font.pw.caption).foregroundStyle(refusal == nil ? Color.pwTextMuted : Color.pwText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func suggest() {
        switch TagSuggestion.add(word, vocabulary: vocabulary.map(\.name), picked: picked, suggested: suggested) {
        case .picked(let name):
            if !picked.contains(name) { picked.append(name) }
            word = ""
        case .suggested(let name):
            suggested.append(name)
            word = ""
        case .refused(let sentence):
            refusal = sentence
        }
    }

    /// A chip is a control: the picked ones wear the tint as a state, the
    /// rest are outlined, as the filter sheet's are.
    private func chip(_ text: String, symbol: String, filled: Bool, dashed: Bool = false, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text).font(Font.pw.footnoteSemibold)
                Image(systemName: symbol).font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            .foregroundStyle(filled ? Color.white : Color.pwText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(filled ? Color.pwAccent : Color.pwSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.clear : Color.pwBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Appearance

/// The tile, folded away because it is optional and editable later: a live
/// miniature of what the quilt will draw, Rotate, the palettes, the blocks,
/// and the motif. The block drafter and the fabric wall stay the website's.
struct AppearancePicker: View {
    @Binding var draft: PatchDraft
    let tagMotifs: [String: String]
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 16) {
                Text("How this patch looks on the quilt. You can change it anytime in Patch Settings → Appearance, and draft your own block there too.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 16) {
                    if let preview = draft.preview(id: "new-patch") {
                        TileMiniature(patch: preview, tagMotifs: tagMotifs, fit: .tile, side: 84)
                            .accessibilityIdentifier("tilePreview")
                    }
                    Button { draft.rotate() } label: { Label("Rotate", systemImage: "rotate.right").font(Font.pw.subheadlineSemibold) }
                        .buttonStyle(.bordered)
                        .tint(Color.pwText)
                        .accessibilityHint("Turns the block a quarter.")
                        .accessibilityIdentifier("rotateTile")
                }
                Text("Palette").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(QuiltTheme.palettes, id: \.self) { palette in
                        let key = palette.key ?? ""
                        Button { draft.palette = key } label: { PaletteSwatch(palette: palette, selected: draft.palette == key) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(palette.name)
                            .accessibilityAddTraits(draft.palette == key ? .isSelected : [])
                            .accessibilityIdentifier("palette-\(key)")
                    }
                }
                Text("Block").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(Array(QuiltBlocks.keys.enumerated()), id: \.element) { index, key in
                        Button { draft.block = key } label: {
                            BlockSwatch(block: key, palette: QuiltTheme.byKey[draft.palette] ?? QuiltTheme.palettes[0], selected: draft.block == key)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(QuiltBlocks.names[index])
                        .accessibilityAddTraits(draft.block == key ? .isSelected : [])
                        .accessibilityIdentifier("block-\(key)")
                    }
                }
                Text("Motif").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
                Text("Optional. The mark that appears beside the name on the quilt. Unset, it follows your first tag. You can change it later in Patch Settings.")
                    .font(Font.pw.caption).foregroundStyle(Color.pwTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                    ForEach(Motifs.keys, id: \.self) { key in
                        Button { draft.toggleMotif(key) } label: { MotifSwatch(key: key, selected: draft.motif == key) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Motifs.name(key))
                            .accessibilityAddTraits(draft.motif == key ? .isSelected : [])
                            .accessibilityIdentifier("motif-\(key)")
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Text("Appearance (optional)").font(Font.pw.footnoteSemibold).foregroundStyle(Color.pwTextMuted)
        }
        .tint(Color.pwText)
        .accessibilityIdentifier("appearanceFold")
    }
}

extension Motifs {
    /// A motif's name, from its registry key: "musicNotes" → "Music notes".
    static func name(_ key: String) -> String {
        var words: [String] = []
        var current = ""
        for character in key {
            if character.isUppercase, !current.isEmpty { words.append(current); current = "" }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ").lowercased()
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}

/// A pre-cut bundle as three stripes of its fabrics.
private struct PaletteSwatch: View {
    let palette: QuiltTheme.Palette
    let selected: Bool
    var body: some View {
        HStack(spacing: 0) {
            ForEach([palette.primary, palette.secondary, palette.bg], id: \.self) { hex in
                Color(UIColor(hex: hex) ?? .clear)
            }
        }
        .frame(width: 48, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(selected ? Color.pwAccent : Color.pwBorder, lineWidth: selected ? 2.5 : 1))
        .frame(minWidth: 48, minHeight: 44)
    }
}

/// One curated block in the chosen palette, unrotated and unmarked: the
/// block alone, the way the web's thumbnails show it.
private struct BlockSwatch: View {
    let block: String
    let palette: QuiltTheme.Palette
    let selected: Bool
    var body: some View {
        Canvas { context, size in
            for cut in QuiltBlocks.cuts(id: block, appearance: Appearance(block: .curated(block)), palette: palette) {
                guard let color = UIColor(hex: cut.hex).map(Color.init) else { continue }
                var path = Path()
                path.addLines(cut.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                path.closeSubpath()
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(selected ? Color.pwAccent : Color.pwBorder, lineWidth: selected ? 2.5 : 1))
    }
}

private struct MotifSwatch: View {
    let key: String
    let selected: Bool
    var body: some View {
        Group {
            if let image = Motifs.image(key) {
                Image(uiImage: image).renderingMode(.template).resizable().frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.pwText)
        .frame(width: 40, height: 40)
        .background(selected ? Color.pwAccent : Color.pwSurface, in: Circle())
        .overlay(Circle().strokeBorder(selected ? Color.clear : Color.pwBorder, lineWidth: 1))
        .frame(width: 44, height: 44)
    }
}
