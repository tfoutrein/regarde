import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// Rendu de l'encre — specification § 6.4
//
// Trois couches, pour que le trait en cours ne force pas la recomposition de ce qui
// est deja pose :
//
//   committed  les traits termines, rasterises — cout de recomposition nul
//   live       le trait en cours, un SEUL CAShapeLayer
//   badges     les numeros (lot 2 ; la couche existe deja pour figer l'ordre de z)
//
// CATransaction.setDisableActions(true) est obligatoire : sans lui, Core Animation
// anime implicitement `path` et le trait arrive avec 0,25 s de retard. Ce n'est pas
// une optimisation, c'est la difference entre un outil utilisable et un outil qui
// donne l'impression d'etre casse.
// ─────────────────────────────────────────────────────────────────────────────

final class InkView: NSView {

    private let committed = CAShapeLayer()
    private let live = CAShapeLayer()
    private let badges = CALayer()

    private var livePoints: [CGPoint] = []
    private var committedPath = CGMutablePath()
    /// Traits termines, conserves pour ⌘Z.
    private var strokes: [CGPath] = []

    private var link: CADisplayLink?

    /// Appele a chaque cycle de rendu du display link de CETTE vue. Seule la vue
    /// designee comme pilote par le controleur s'en sert pour declencher le drainage.
    var onFrame: (() -> Void)?

    /// Renseigne par le controleur : convertit un point `CGEvent.location` en
    /// coordonnees locales de cette vue.
    var eventToLocal: ((CGPoint) -> CGPoint)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setupLayers()
        // Reserver la capacite une fois : `append` dans le chemin de rendu ne doit
        // pas declencher de reallocation au milieu d'un trait.
        livePoints.reserveCapacity(4096)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilise") }

    private func setupLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        for l in [committed, live] {
            l.fillColor = nil
            l.strokeColor = NSColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1.0).cgColor // #FF3B30
            l.lineWidth = 3
            l.lineCap = .round
            l.lineJoin = .round
            // Aucune ombre, aucun flou, aucun NSVisualEffectView : chacun de ces effets
            // est une passe de composition supplementaire, et le § 12 R8 en fait un
            // risque explicite — l'outil deviendrait la lenteur qu'il sert a diagnostiquer.
            l.shadowOpacity = 0
            l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
        }

        // Les traits poses ne changent plus : les rasteriser rend leur recomposition
        // gratuite pendant que le trait vivant, lui, se redessine a chaque frame.
        committed.shouldRasterize = true
        committed.rasterizationScale = window?.backingScaleFactor ?? 2.0

        root.addSublayer(committed)
        root.addSublayer(live)
        root.addSublayer(badges)
        layoutLayers()
    }

    func layoutLayers() {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [committed, live, badges] { l.frame = root.bounds }
        committed.rasterizationScale = window?.backingScaleFactor ?? 2.0
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        committed.rasterizationScale = window?.backingScaleFactor ?? 2.0
    }

    // MARK: - Display link

    func startRendering() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stopRendering() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ sender: CADisplayLink) {
        // Le drainage n'a PAS lieu ici. `InkRing` est un ring a consommateur unique et
        // `drain` avance la queue : avec un display link par ecran, le premier declenche
        // emporterait tout et l'autre trouverait la file vide — un tracé sur deux ne
        // dessinerait rien, et les points seraient convertis par le mauvais panneau.
        // Le controleur draine une fois et diffuse a tous les panneaux.
        onFrame?()
    }

    // MARK: - Consommation

    /// Applique un evenement. Appelee par le controleur, sur le thread principal,
    /// pour CHAQUE panneau — la conversion `eventToLocal` place le point hors des
    /// bornes des panneaux qui ne sont pas concernes, et le WindowServer le clippe.
    ///
    /// La diffusion est preferable a un routage par ecran : un trait qui traverse la
    /// frontiere entre deux ecrans resterait continu, la ou un routage le couperait en
    /// deux sur le `guard !livePoints.isEmpty`.
    func consume(_ event: InkEvent) {
        let local = eventToLocal?(event.point) ?? event.point

        switch event.eventKind {
        case .down:
            livePoints.removeAll(keepingCapacity: true)
            livePoints.append(local)

        case .drag:
            // Un mouseMoved sans tracé en cours ne doit pas allonger le trait : il n'y a
            // pas de bouton enfonce, c'est de la visee. Le reticule viendra au lot 2.
            guard !livePoints.isEmpty else { return }
            // Filtrer les points quasi identiques : une souris a 1000 Hz en emet des
            // dizaines par pixel, tous rigoureusement inutiles au trace.
            if let last = livePoints.last, hypot(local.x - last.x, local.y - last.y) < 0.75 { return }
            livePoints.append(local)

        case .up:
            guard !livePoints.isEmpty else { return }
            livePoints.append(local)
            commitStroke()
        }
    }

    /// Publie le trait vivant. Une seule transaction par cycle, pour tout le lot
    /// d'evenements draines — c'est ce qui remplace les mille reveils par seconde
    /// qu'un `async` par point produirait.
    func commitFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        live.path = pathFromLivePoints()
        CATransaction.commit()
    }

    private func pathFromLivePoints() -> CGPath? {
        guard livePoints.count > 1 else { return nil }
        let p = CGMutablePath()
        p.addLines(between: livePoints)
        return p
    }

    /// Plus grand nombre de points atteint par un trait vivant.
    ///
    /// Le § 6.4 prevoit de figer la tete du trait et de borner la queue a ~200 points ;
    /// ce prototype ne le fait pas, et reconstruit le chemin entier a chaque cycle. Le
    /// cout client est negligeable, celui du render server ne l'est peut-etre pas — il
    /// re-tesselise N segments a joints ronds par frame, dans le processus partage avec
    /// l'application testee.
    ///
    /// On ne corrige pas a l'aveugle : ce compteur, croise avec la comparaison des cinq
    /// premieres et des cinq dernieres secondes du relevé C3b, dira si la degradation
    /// est un plateau (defaut cosmetique, ne pas y toucher) ou une rampe (a traiter).
    private(set) var maxLivePoints = 0

    private func commitStroke() {
        maxLivePoints = max(maxLivePoints, livePoints.count)
        // Decimation Ramer-Douglas-Peucker a la fin du trait, pas pendant : simplifier
        // en direct ferait sauter la tete du trait sous le curseur.
        let simplified = InkView.decimate(livePoints, epsilon: 0.6)
        guard simplified.count > 1 else { livePoints.removeAll(keepingCapacity: true); return }

        let stroke = CGMutablePath()
        stroke.addLines(between: simplified)
        strokes.append(stroke)
        committedPath.addPath(stroke)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        committed.path = committedPath
        live.path = nil
        CATransaction.commit()

        livePoints.removeAll(keepingCapacity: true)
    }

    /// Annule le trait en cours (Échap). Le trait disparait, rien n'est pose.
    func cancelLiveStroke() {
        livePoints.removeAll(keepingCapacity: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        live.path = nil
        CATransaction.commit()
    }

    /// Supprime le dernier trait pose (⌘Z).
    func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        let rebuilt = CGMutablePath()
        for s in strokes { rebuilt.addPath(s) }
        committedPath = rebuilt

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        committed.path = strokes.isEmpty ? nil : committedPath
        CATransaction.commit()
    }

    func clearAll() {
        strokes.removeAll()
        committedPath = CGMutablePath()
        livePoints.removeAll(keepingCapacity: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        committed.path = nil
        live.path = nil
        CATransaction.commit()
    }

    var strokeCount: Int { strokes.count }
    var hasContent: Bool { !strokes.isEmpty || !livePoints.isEmpty }

    // MARK: - Ramer-Douglas-Peucker

    /// Simplification iterative : la version recursive deborde la pile sur un trait
    /// de plusieurs milliers de points, ce qui arrive en quelques secondes a 1000 Hz.
    static func decimate(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            var maxDist: CGFloat = 0
            var index = first

            for i in (first + 1)..<last {
                let d = perpendicularDistance(points[i], points[first], points[last])
                if d > maxDist { maxDist = d; index = i }
            }

            if maxDist > epsilon {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }

        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func perpendicularDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let denom = dx * dx + dy * dy
        guard denom > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / sqrt(denom)
    }
}
