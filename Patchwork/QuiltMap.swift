// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import MapKit

/// Where the camera was when the reader last left the map, so switching to
/// the quilt and back returns them to the street they were reading rather
/// than re-framing the whole community. Held outside SwiftUI's state so
/// every pan does not redraw the browser around it.
final class MapMemory {
    var quilt: String?
    var camera: MKMapCamera?
}

/// The map pane (docs/adr/078: the map says where, the card says who).
///
/// What it keeps from the web: identity-coloured teardrops wearing the
/// patch's motif; clusters as neutral count discs, which zoom to their
/// members; names as halo'd text placed by separation, heaviest patch first;
/// a fit on the first paint and never again, so narrowing never moves the
/// map; and a sentence, not a jump, when every match is out of view.
///
/// What it leaves to the platform: MapKit's own cartography in its muted
/// register (the web's Positron is the same idea), pinch and the compass
/// rather than zoom buttons, the legal label where MapKit puts it, and the
/// patch sheet as the preview a tap summons.
struct QuiltMap: View {
    let patches: [Patch]
    /// Whether anything in the whole quilt — filter or no — has a location,
    /// which decides between an empty map and no map at all.
    let quiltHasLocations: Bool
    let tagMotifs: [String: String]
    let colorMode: ColorMode
    let docked: String?
    let memory: MapMemory
    let quiltID: String
    let open: (Patch) -> Void
    @State private var offscreen = 0
    @State private var showAll = 0
    @State private var crowd: [Patch] = []

    private var located: [Patch] { patches.filter(\.isPlaced) }

    var body: some View {
        if !quiltHasLocations {
            ContentUnavailableView("No locations to show", systemImage: "map",
                                   description: Text("These patches haven’t shared map coordinates."))
        } else {
            GeometryReader { geo in
                PatchMapView(patches: located,
                             look: "\(colorMode)|\(tagMotifs.count)",
                             tagMotifs: tagMotifs,
                             docked: docked,
                             insets: UIEdgeInsets(top: geo.safeAreaInsets.top, left: geo.safeAreaInsets.leading,
                                                  bottom: geo.safeAreaInsets.bottom, right: geo.safeAreaInsets.trailing),
                             showAll: showAll,
                             memory: memory,
                             quiltID: quiltID,
                             open: open,
                             offscreen: { offscreen = $0 },
                             crowd: { crowd = $0 })
                    .ignoresSafeArea()
            }
            .overlay(alignment: .top) { notice.padding(.top, 8) }
            .confirmationDialog("\(crowd.count) patches here", isPresented: Binding(get: { !crowd.isEmpty }, set: { if !$0 { crowd = [] } }),
                                titleVisibility: .visible) {
                ForEach(crowd) { patch in Button(patch.name) { open(patch) } }
            } message: {
                Text("These patches share one spot on the map.")
            }
        }
    }

    /// Narrowing never moves the map, which leaves two cases a reader cannot
    /// explain to themselves: everything that matches is somewhere else, or
    /// nothing that matches has a place at all. Each gets one sentence.
    @ViewBuilder private var notice: some View {
        if located.isEmpty {
            Text("No matching patches are on the map")
                .font(Font.pw.footnote)
                .foregroundStyle(Color.pwText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .modifier(GlassCapsule())
                .accessibilityIdentifier("mapNoneLocated")
        } else if offscreen > 0 {
            Button { showAll += 1 } label: {
                Group {
                    if offscreen == 1 { Text("**1** patch is outside this view") }
                    else { Text("**\(offscreen)** patches are outside this view") }
                }
                .font(Font.pw.footnote.monospacedDigit())
                .foregroundStyle(Color.pwText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modifier(GlassCapsule())
            .accessibilityHint("Shows every matching patch")
            .accessibilityIdentifier("mapOffscreen")
        }
    }
}

extension Patch {
    /// Has a usable point on the map.
    var isPlaced: Bool {
        guard let latitude, let longitude else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude ?? 0, longitude: longitude ?? 0) }
}

// MARK: - The MapKit view

private struct PatchMapView: UIViewRepresentable {
    let patches: [Patch]
    let look: String
    let tagMotifs: [String: String]
    let docked: String?
    let insets: UIEdgeInsets
    let showAll: Int
    let memory: MapMemory
    let quiltID: String
    let open: (Patch) -> Void
    let offscreen: (Int) -> Void
    let crowd: ([Patch]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PaperMapView {
        let map = PaperMapView()
        // MapKit's muted register is the native cousin of the web's Positron:
        // quiet cartography that lets the patches be the colour on the page.
        // Apple's own points of interest are left off — a café pin beside a
        // patch pin would be a second kind of place nobody asked for.
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.selectableMapFeatures = []
        map.showsCompass = true
        map.showsScale = true
        map.delegate = context.coordinator
        map.register(PatchPinView.self, forAnnotationViewWithReuseIdentifier: PatchPinView.reuse)
        map.register(PatchClusterView.self, forAnnotationViewWithReuseIdentifier: PatchClusterView.reuse)
        map.addOverlay(PaperTint.shared, level: .aboveRoads)
        map.onLayout = { [weak coordinator = context.coordinator] in coordinator?.laidOut() }
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: PaperMapView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleUIView(_ map: PaperMapView, coordinator: Coordinator) {
        coordinator.remember()
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: PaperMapView?
        private var parent: PatchMapView?
        private var byID: [String: Patch] = [:]
        private var order: [Patch] = []
        private var lone: [String: PatchAnnotation] = [:]
        private var clusters: [String: ClusterAnnotation] = [:]
        private var slots: [String: MapPlacement.Slot] = [:]
        private var look = ""
        private var docked: String?
        private var fitted = false
        private var showAllSeen = 0
        private var reportedOffscreen = -1
        /// The last cluster a tap zoomed toward, so a second tap that finds
        /// the same members still piled up offers them as a list instead.
        private var lastClusterTap: String?

        func update(_ next: PatchMapView) {
            let first = parent == nil
            parent = next
            guard let map else { return }
            if first { showAllSeen = next.showAll }
            order = next.patches
            byID = Dictionary(next.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            if look != next.look {
                look = next.look
                map.removeAnnotations(map.annotations)
                lone = [:]; clusters = [:]
            }
            let dockChanged = docked != next.docked
            docked = next.docked
            if next.showAll != showAllSeen {
                showAllSeen = next.showAll
                frameAll(animated: true)
            }
            fitIfNeeded()
            regroup()
            if dockChanged, let id = docked { keepClearOfSheet(id) }
        }

        func laidOut() {
            fitIfNeeded()
            regroup()
        }

        func remember() {
            guard let map, let parent, fitted else { return }
            parent.memory.quilt = parent.quiltID
            parent.memory.camera = map.camera.copy() as? MKMapCamera
        }

        // MARK: Framing

        /// The first paint that has something to frame is framed, and nothing
        /// after it is: narrowing a set is not a request to be moved.
        private func fitIfNeeded() {
            guard !fitted, let map, let parent, map.bounds.width > 0, !order.isEmpty else { return }
            fitted = true
            if parent.memory.quilt == parent.quiltID, let camera = parent.memory.camera {
                map.setCamera(camera, animated: false)
            } else {
                frameAll(animated: false)
            }
        }

        /// Animated only when a person asked for it: the motion tells them
        /// where they were taken. The opening fit is never animated.
        private func frameAll(animated: Bool) {
            guard let map, let parent, !order.isEmpty else { return }
            let pad = UIEdgeInsets(top: parent.insets.top + 48, left: parent.insets.left + 24,
                                   bottom: parent.insets.bottom + 72, right: parent.insets.right + 24)
            map.setVisibleMapRect(Self.rect(around: order.map(\.coordinate)), edgePadding: pad, animated: animated)
        }

        /// The members' bounds, never smaller than a few streets, so a lone
        /// patch is framed in its neighbourhood rather than at roof height.
        private static func rect(around coordinates: [CLLocationCoordinate2D], minimum: CLLocationDistance = 600) -> MKMapRect {
            let points = coordinates.map(MKMapPoint.init)
            var rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0))) }
            let floor = minimum * MKMapPointsPerMeterAtLatitude(coordinates.first?.latitude ?? 0)
            if rect.size.width < floor { rect = rect.insetBy(dx: -(floor - rect.size.width) / 2, dy: 0) }
            if rect.size.height < floor { rect = rect.insetBy(dx: 0, dy: -(floor - rect.size.height) / 2) }
            return rect
        }

        /// A preview is a sheet over the map's foot; a pin it would cover is
        /// lifted above it, the way Maps keeps a chosen place in sight.
        private func keepClearOfSheet(_ id: String) {
            guard let map, let patch = byID[id], lone[id] != nil else { return }
            let p = map.convert(patch.coordinate, toPointTo: map)
            let sheetTop = map.bounds.height - 360
            guard p.y > sheetTop || p.y < (parent?.insets.top ?? 0) + 40 else { return }
            let target = CGPoint(x: map.bounds.midX, y: map.bounds.midY + (p.y - max(sheetTop * 0.55, 140)))
            map.setCenter(map.convert(target, toCoordinateFrom: map), animated: true)
        }

        // MARK: Grouping and names

        /// The map a reader can actually see: under the bars, over the tab bar.
        private var visible: CGRect {
            guard let map, let parent else { return .zero }
            return map.bounds.inset(by: parent.insets).insetBy(dx: 4, dy: 4)
        }

        private func regroup() {
            guard let map, fitted, map.bounds.width > 0 else { report(offscreen: 0); return }
            var at: [String: CGPoint] = [:]
            for patch in order { at[patch.id] = map.convert(patch.coordinate, toPointTo: map) }
            let points = order.map { MapPlacement.Point(id: $0.id, activity: MapPlacement.activity($0), at: at[$0.id]!) }
            let groups = MapPlacement.cluster(points)
            func centre(_ group: MapPlacement.Group) -> CGPoint {
                let pts = group.members.compactMap { at[$0] }
                return CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
            }
            let font = PatchPinView.nameFont
            slots = MapPlacement.names(for: groups, at: centre, size: { [byID] in PatchPinView.nameSize(byID[$0]?.name ?? "", font: font) },
                                       incumbents: Set(slots.keys), visible: visible)

            // Diff rather than rebuild: a marker that stays a marker keeps
            // its view, so a pinch only ever adds and removes what changed.
            let wantLone = Set(groups.filter { !$0.isCluster }.map(\.lead))
            let wantClusters = Dictionary(groups.filter(\.isCluster).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            let goneLone = lone.filter { !wantLone.contains($0.key) }
            let goneClusters = clusters.filter { wantClusters[$0.key] == nil }
            map.removeAnnotations(Array(goneLone.values) + Array(goneClusters.values))
            goneLone.keys.forEach { lone[$0] = nil }
            goneClusters.keys.forEach { clusters[$0] = nil }
            var added: [MKAnnotation] = []
            for id in wantLone {
                guard let patch = byID[id] else { continue }
                if let existing = lone[id] { existing.patch = patch; continue }
                let annotation = PatchAnnotation(patch)
                lone[id] = annotation
                added.append(annotation)
            }
            for (key, group) in wantClusters where clusters[key] == nil {
                let members = group.members.compactMap { byID[$0] }
                let annotation = ClusterAnnotation(key: key, members: members)
                clusters[key] = annotation
                added.append(annotation)
            }
            map.addAnnotations(added)
            for (id, annotation) in lone { (map.view(for: annotation) as? PatchPinView).map { dress($0, id: id) } }

            let seen = order.filter { at[$0.id].map(visible.contains) ?? false }.count
            report(offscreen: seen == 0 ? order.count : 0)
        }

        private func dress(_ view: PatchPinView, id: String) {
            guard let map, let patch = byID[id] else { return }
            let previewing = docked == id
            var slot = slots[id]
            // A tapped marker's name is shown whether or not it won a place.
            if slot == nil && previewing {
                let p = map.convert(patch.coordinate, toPointTo: map)
                slot = MapPlacement.revealed(at: p, size: PatchPinView.nameSize(patch.name, font: PatchPinView.nameFont), visible: visible)
            }
            view.dress(patch: patch, tagMotifs: parent?.tagMotifs ?? [:], slot: slot, previewing: previewing)
        }

        private func report(offscreen count: Int) {
            guard count != reportedOffscreen else { return }
            reportedOffscreen = count
            let send = parent?.offscreen
            DispatchQueue.main.async { send?(count) }
        }

        // MARK: Taps

        func tapped(_ annotation: MKAnnotation) {
            guard let map, let parent else { return }
            if let pin = annotation as? PatchAnnotation {
                lastClusterTap = nil
                parent.open(pin.patch)
                return
            }
            guard let cluster = annotation as? ClusterAnnotation else { return }
            // Two patches at one address never separate however far in the
            // map goes; a pile that cannot be pulled apart is offered as a
            // list instead of a zoom that changes nothing.
            if lastClusterTap == cluster.key || cluster.spread < 8 {
                lastClusterTap = nil
                parent.crowd(cluster.members.sorted { MapPlacement.activity($0) > MapPlacement.activity($1) })
                return
            }
            lastClusterTap = cluster.key
            let pad = UIEdgeInsets(top: parent.insets.top + 60, left: parent.insets.left + 60,
                                   bottom: parent.insets.bottom + 60, right: parent.insets.right + 60)
            map.setVisibleMapRect(Self.rect(around: cluster.members.map(\.coordinate), minimum: 60), edgePadding: pad, animated: true)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let pin = annotation as? PatchAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: PatchPinView.reuse, for: pin) as! PatchPinView
                view.onTap = { [weak self, weak pin] in if let pin { self?.tapped(pin) } }
                dress(view, id: pin.patch.id)
                return view
            }
            if let cluster = annotation as? ClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: PatchClusterView.reuse, for: cluster) as! PatchClusterView
                view.onTap = { [weak self, weak cluster] in if let cluster { self?.tapped(cluster) } }
                view.dress(cluster)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views {
                view.alpha = 0
                UIView.animate(withDuration: 0.18) { view.alpha = 1 }
            }
        }

        /// Selection is the tap gesture's job; MapKit's own is let go at once.
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            regroup()
            if let key = lastClusterTap, clusters[key] == nil { lastClusterTap = nil }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tint = overlay as? PaperTint { return PaperTintRenderer(overlay: tint, map: mapView) }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// The map view itself, reporting its first real size so the opening fit
/// can wait for one, and repainting the paper tint when the theme turns.
final class PaperMapView: MKMapView {
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (map: PaperMapView, _: UITraitCollection) in
            map.overlays.forEach { (map.renderer(for: $0) as? PaperTintRenderer)?.repaint() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?()
    }
}

// MARK: - Annotations

private final class PatchAnnotation: NSObject, MKAnnotation {
    var patch: Patch
    let coordinate: CLLocationCoordinate2D
    init(_ patch: Patch) { self.patch = patch; coordinate = patch.coordinate }
    var title: String? { patch.name }
}

private final class ClusterAnnotation: NSObject, MKAnnotation {
    let key: String
    let members: [Patch]
    /// A cluster sits at its members' mean.
    let coordinate: CLLocationCoordinate2D
    init(key: String, members: [Patch]) {
        self.key = key
        self.members = members
        let n = Double(max(members.count, 1))
        coordinate = CLLocationCoordinate2D(latitude: members.map { $0.latitude ?? 0 }.reduce(0, +) / n,
                                            longitude: members.map { $0.longitude ?? 0 }.reduce(0, +) / n)
    }
    /// The widest distance between two members, in metres.
    var spread: CLLocationDistance {
        let points = members.map { MKMapPoint($0.coordinate) }
        var widest: CLLocationDistance = 0
        for (i, a) in points.enumerated() { for b in points[(i + 1)...] { widest = max(widest, a.distance(to: b)) } }
        return widest
    }
}

// MARK: - The patch's pin

/// A quilt-coloured teardrop: the patch's identity colour, which is the same
/// colour its tile wears, carrying its motif and nothing else — the card says
/// who runs it and what it is to you. Its name, when it has won one, stands
/// beside it as halo'd text rather than a pill: a basemap is not fabric.
private final class PatchPinView: MKAnnotationView {
    static let reuse = "patch"
    var onTap: (() -> Void)?
    private let body = UIImageView()
    private let name = UIImageView()
    private var patchName = ""
    private var slot: MapPlacement.Slot?
    private let size = MapPlacement.markerSize

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(origin: .zero, size: size)
        // The tip, not the middle, is the coordinate.
        centerOffset = CGPoint(x: 0, y: -size.height / 2)
        displayPriority = .required
        collisionMode = .none
        canShowCallout = false
        clipsToBounds = false
        body.frame = bounds
        body.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        body.layer.position = CGPoint(x: size.width / 2, y: size.height)
        body.layer.shadowColor = UIColor.black.cgColor
        body.layer.shadowPath = Self.teardrop.cgPath
        addSubview(body)
        addSubview(name)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Shows this patch"
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: PatchPinView, _: UITraitCollection) in
            view.paintName()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tap() { onTap?() }

    /// A name is part of its marker: a tap on it is a tap on the patch.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || (!name.isHidden && name.frame.contains(point))
    }

    func dress(patch: Patch, tagMotifs: [String: String], slot: MapPlacement.Slot?, previewing: Bool) {
        let fill = QuiltTheme.palette(for: patch).primary
        body.image = Self.pin(fill: fill, motif: Motifs.key(for: patch, tagMotifs: tagMotifs))
        // Heavier patches sit on top, so the marker you can tap is the one
        // whose name you can read; the previewed one above them all.
        zPriority = previewing ? .max : MKAnnotationViewZPriority(rawValue: 100 + Float(min(MapPlacement.activity(patch), 500)) * 1.5)
        accessibilityLabel = patch.name
        // The previewed pin lifts toward the reader, standing on its point.
        UIView.animate(withDuration: 0.16) {
            self.body.transform = previewing ? CGAffineTransform(scaleX: 1.25, y: 1.25) : .identity
            self.body.layer.shadowOffset = CGSize(width: 0, height: previewing ? 3 : 2)
            self.body.layer.shadowRadius = previewing ? 2.5 : 1.2
            self.body.layer.shadowOpacity = previewing ? 0.5 : 0.3
        }
        let changed = patch.name != patchName || slot != self.slot
        patchName = patch.name
        self.slot = slot
        if changed { paintName() }
    }

    private func paintName() {
        guard let slot, !patchName.isEmpty else { name.isHidden = true; return }
        let font = Self.nameFont
        let text = Self.nameSize(patchName, font: font)
        let tip = CGPoint(x: size.width / 2, y: size.height)
        name.image = Self.halo(patchName, font: font, traits: traitCollection)
        name.frame = slot.frame(text).offsetBy(dx: tip.x, dy: tip.y).insetBy(dx: -Self.haloPad, dy: -Self.haloPad)
        name.isHidden = false
    }

    // MARK: Drawing

    /// The web's teardrop (`M12 0C5.4 0 0 5.4 0 12c0 9 12 20 12 20s12-11 12-20C24 5.4 18.6 0 12 0z`),
    /// scaled into the marker's box with room for its hairline.
    static let teardrop: UIBezierPath = {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 12, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: 12), controlPoint1: CGPoint(x: 5.4, y: 0), controlPoint2: CGPoint(x: 0, y: 5.4))
        path.addCurve(to: CGPoint(x: 12, y: 32), controlPoint1: CGPoint(x: 0, y: 21), controlPoint2: CGPoint(x: 12, y: 32))
        path.addCurve(to: CGPoint(x: 24, y: 12), controlPoint1: CGPoint(x: 12, y: 32), controlPoint2: CGPoint(x: 24, y: 21))
        path.addCurve(to: CGPoint(x: 12, y: 0), controlPoint1: CGPoint(x: 24, y: 5.4), controlPoint2: CGPoint(x: 18.6, y: 0))
        path.close()
        let scale = min((MapPlacement.markerSize.width - 1) / 24, (MapPlacement.markerSize.height - 1) / 32)
        path.apply(CGAffineTransform(scaleX: scale, y: scale))
        path.apply(CGAffineTransform(translationX: (MapPlacement.markerSize.width - 24 * scale) / 2, y: 0.5))
        return path
    }()

    private static var pins: [String: UIImage] = [:]

    static func pin(fill: String, motif: String) -> UIImage {
        let key = fill + "|" + motif
        if let cached = pins[key] { return cached }
        let size = MapPlacement.markerSize
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            (UIColor(hex: fill) ?? .gray).setFill()
            teardrop.fill()
            UIColor(white: 0, alpha: 0.35).setStroke()
            teardrop.lineWidth = 1
            teardrop.stroke()
            // The motif, in ink or paper against the fill, centred in the head.
            let glyph = Motifs.image(motif)?.withTintColor(QuiltTheme.textOnColor(fill), renderingMode: .alwaysOriginal)
            let side: CGFloat = 13
            glyph?.draw(in: CGRect(x: (size.width - side) / 2, y: 13 - side / 2 + 0.5, width: side, height: side))
        }
        pins[key] = image
        return image
    }

    /// Caption-sized, following the reader's text size up to a bound a map
    /// can carry, in the quilt's own face — the same rule as its badges.
    static var nameFont: UIFont {
        PWType.baseFont(.text, size: min(UIFont.preferredFont(forTextStyle: .caption1).pointSize, 17), weight: 600)
    }

    private static var widths: [String: CGSize] = [:]
    static func nameSize(_ text: String, font: UIFont) -> CGSize {
        let key = "\(font.pointSize)|\(text)"
        if let cached = widths[key] { return cached }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let size = CGSize(width: ceil(width), height: ceil(font.lineHeight))
        widths[key] = size
        return size
    }

    static let haloPad: CGFloat = 3

    /// Ink with a stroke of the ground under it, so the name reads over any
    /// street the basemap draws — the web's `paint-order: stroke fill`.
    static func halo(_ text: String, font: UIFont, traits: UITraitCollection) -> UIImage {
        let ink = UIColor(named: "PWText")?.resolvedColor(with: traits) ?? .label
        let ground = UIColor.pwGround.resolvedColor(with: traits)
        let size = nameSize(text, font: font)
        let canvas = CGSize(width: size.width + 2 * haloPad, height: size.height + 2 * haloPad)
        let format = UIGraphicsImageRendererFormat(for: traits)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let origin = CGPoint(x: haloPad, y: haloPad)
            let shadow = NSShadow()
            shadow.shadowColor = ground
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            (text as NSString).draw(at: origin, withAttributes: [
                .font: font, .foregroundColor: ground, .strokeColor: ground,
                .strokeWidth: 3 / font.pointSize * 100, .shadow: shadow,
            ])
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: ink])
        }
    }
}

// MARK: - A cluster

/// A cluster is not a patch, so it wears no identity colour, no motif and no
/// name — the neutral dark disc the quilt gives to status, and a count.
private final class PatchClusterView: MKAnnotationView {
    static let reuse = "cluster"
    var onTap: (() -> Void)?
    private let disc = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .required
        collisionMode = .circle
        canShowCallout = false
        zPriority = MKAnnotationViewZPriority(rawValue: 50)
        addSubview(disc)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 1.5
        layer.shadowOpacity = 0.4
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tap() { onTap?() }

    func dress(_ cluster: ClusterAnnotation) {
        let count = cluster.members.count
        let side = MapPlacement.discSide(count)
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        disc.frame = bounds
        disc.image = Self.disc(count)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
        accessibilityLabel = "\(count) patches: " + cluster.members.map(\.name).joined(separator: ", ")
        accessibilityHint = cluster.spread < 8 ? "Lists them" : "Zooms in to them"
    }

    private static var discs: [Int: UIImage] = [:]

    static func disc(_ count: Int) -> UIImage {
        if let cached = discs[count] { return cached }
        let side = MapPlacement.discSide(count)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let ring = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
            UIColor(hex: "#1f2226")?.setFill()
            ring.fill()
            UIColor(white: 1, alpha: 0.85).setStroke()
            ring.lineWidth = 2
            ring.stroke()
            let font = UIFont.monospacedDigitSystemFont(ofSize: side * 0.4, weight: .semibold)
            let text = "\(count)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attrs)
        }
        discs[count] = image
        return image
    }
}

// MARK: - The paper

/// A wash of the app's ground laid over the basemap, under its labels, so
/// the map reads as the same cotton as the rest of the app rather than a
/// grey rectangle let into it — the web warms its tiles toward its paper
/// for the same reason. Light enough that the streets stay streets.
private final class PaperTint: NSObject, MKOverlay {
    static let shared = PaperTint()
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
}

private final class PaperTintRenderer: MKOverlayRenderer {
    private weak var map: MKMapView?
    private var color: CGColor

    init(overlay: MKOverlay, map: MKMapView) {
        self.map = map
        color = Self.wash(map.traitCollection)
        super.init(overlay: overlay)
    }

    private static func wash(_ traits: UITraitCollection) -> CGColor {
        UIColor.pwGround.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.28 : 0.32).cgColor
    }

    func repaint() {
        guard let map else { return }
        color = Self.wash(map.traitCollection)
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setFillColor(color)
        context.fill(rect(for: mapRect))
    }
}
