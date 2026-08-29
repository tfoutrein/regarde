import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// Rendu de l'encre — spécification § 6.4
//
// Trois couches, pour que le trait en cours ne force pas la recomposition de ce qui est
// déjà posé :
//
//   committed  les marques terminées, rasterisées — coût de recomposition nul
//   live       la marque en cours, un SEUL CAShapeLayer par mode de peinture
//   badges     les numéros (S21 et S23)
//
// Chaque étage se dédouble en trois modes de peinture, parce qu'un `CAShapeLayer` n'a
// qu'un `fillColor` et qu'un `strokeColor` pour tout son chemin : trait opaque, aplat
// opaque, aplat translucide. Le surlignage doit laisser lire l'interface dessous, donc
// il ne peut pas partager la couche du trait.
//
// `CATransaction.setDisableActions(true)` est obligatoire : sans lui, Core Animation
// anime implicitement `path` et le trait arrive avec 0,25 s de retard. Ce n'est pas une
// optimisation, c'est la différence entre un outil utilisable et un outil qui semble
// cassé.
//
// Le gel du rendu sur occlusion (S18) : quand le panneau est masqué — Mission Control,
// un Space voisin — continuer à commiter des transactions coûterait sans rien afficher.
// ─────────────────────────────────────────────────────────────────────────────

final class InkView: NSView {

    /// Un jeu de couches pour un étage : trait, aplat, lavis.
    private struct Painter {
        let stroke = CAShapeLayer()
        let fill = CAShapeLayer()
        let wash = CAShapeLayer()

        var all: [CAShapeLayer] { [wash, fill, stroke] }

        func layer(for rendering: MarkRendering) -> CAShapeLayer {
            switch rendering {
            case .stroke: stroke
            case .fill: fill
            case .wash: wash
            }
        }

        func setPaths(_ paths: [MarkRendering: CGPath]) {
            stroke.path = paths[.stroke]
            fill.path = paths[.fill]
            wash.path = paths[.wash]
        }

        func configure() {
            stroke.fillColor = nil
            stroke.strokeColor = InkStyle.color.cgColor
            stroke.lineWidth = InkStyle.width
            stroke.lineCap = .round
            stroke.lineJoin = .round

            fill.fillColor = InkStyle.color.cgColor
            fill.strokeColor = nil

            // Le lavis porte un liseré à pleine opacité : sans lui, un surlignage sur un
            // fond clair devient un halo aux bords indécis, et la gravure du lot 2 doit
            // pouvoir en désigner la limite exacte.
            wash.fillColor = InkStyle.washColor.cgColor
            wash.strokeColor = InkStyle.color.cgColor
            wash.lineWidth = 1.5

            for l in all {
                // Aucune ombre, aucun flou, aucun `NSVisualEffectView` : chacun est une
                // passe de composition supplémentaire, et le risque R8 en fait un danger
                // explicite — l'outil deviendrait la lenteur qu'il sert à diagnostiquer.
                l.shadowOpacity = 0
                l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            }
        }
    }

    private let committed = Painter()
    private let live = Painter()
    private let badges = CALayer()
    /// Pastilles recyclées d'une frame à l'autre, jamais recréées.
    private var badgePool: [BadgeLayer] = []

    /// Rendu gelé : le panneau est masqué, commiter ne servirait à rien.
    private(set) var isFrozen = false

    private var link: CADisplayLink?

    /// Appelé à chaque cycle du display link. Seule la vue élue par le contrôleur y
    /// branche le drainage — voir `OverlayController.electPump`.
    var onFrame: (() -> Void)?

    /// Appelé quand la vue sort du gel, pour qu'elle reprenne l'état du modèle.
    ///
    /// Sans ce rappel, une vue gelée ignore les ordres de dessin — c'est le but — mais
    /// les ignore DÉFINITIVEMENT : elle réapparaît avec le contenu qu'elle avait avant
    /// d'être masquée. Constaté en usage réel : après une publication, reprendre ⌥⌘ une
    /// minute plus tard faisait ressurgir les marques déjà publiées, sur les deux écrans,
    /// jusqu'au premier point du tracé suivant — et seul l'écran où l'on traçait s'en
    /// débarrassait.
    var onThaw: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    private func setupLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        committed.configure()
        live.configure()

        // Les marques posées ne changent plus : les rasteriser rend leur recomposition
        // gratuite pendant que la marque vivante se redessine à chaque frame.
        for l in committed.all {
            l.shouldRasterize = true
            l.rasterizationScale = window?.backingScaleFactor ?? 2.0
        }

        // Ordre de superposition : les lavis d'abord, puis les aplats, puis les traits.
        // Un surlignage posé après une flèche ne doit pas la voiler.
        for l in committed.all { root.addSublayer(l) }
        for l in live.all { root.addSublayer(l) }
        root.addSublayer(badges)
        layoutLayers()
    }

    func layoutLayers() {
        guard let root = layer else { return }
        transaction {
            for l in committed.all + live.all { l.frame = root.bounds }
            badges.frame = root.bounds
            for l in committed.all { l.rasterizationScale = window?.backingScaleFactor ?? 2.0 }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for l in committed.all { l.rasterizationScale = window?.backingScaleFactor ?? 2.0 }
    }

    /// Une transaction sans animation implicite. Tout passe par ici.
    private func transaction(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - Display link

    /// Démarre la cadence de rendu.
    ///
    /// `CADisplayLink` synchronise sur le rafraîchissement de l'écran, là où un `Timer`
    /// dériverait. Il ne tire que lorsque la fenêtre est à l'écran, ce qui est exactement
    /// le comportement voulu : hors tracé, les panneaux sont retirés (ADR-0010) et rien
    /// ne tourne.
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
        onFrame?()
    }

    // MARK: - Gel sur occlusion (S18)

    func setFrozen(_ frozen: Bool) {
        guard frozen != isFrozen else { return }
        isFrozen = frozen
        // Le dégel resynchronise : tout ce qui a été refusé pendant le gel doit être
        // rattrapé, sans quoi la vue affiche un état périmé.
        if !frozen { onThaw?() }
    }

    // MARK: - Contenu

    /// Publie la marque en cours.
    func setLivePaths(_ paths: [MarkRendering: CGPath]) {
        guard !isFrozen else { return }
        transaction { live.setPaths(paths) }
    }

    /// Publie l'ensemble des marques posées.
    func setCommittedPaths(_ paths: [MarkRendering: CGPath]) {
        guard !isFrozen else { return }
        transaction { committed.setPaths(paths) }
    }

    /// Le numéro dont le badge pulse — celui de la fenêtre de parole ouverte.
    private var pulsingNumber: Int?

    func setPulse(_ number: Int?) {
        pulsingNumber = number
        for badge in badgePool where !badge.isHidden { badge.pulser(badge.numeroAffiche == number) }
    }

    /// Publie les numéros. Le tracé en cours porte le sien, comme les marques posées.
    func setBadges(_ specs: [BadgeSpec]) {
        guard !isFrozen else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        transaction {
            while badgePool.count < specs.count {
                let badge = BadgeLayer()
                badges.addSublayer(badge)
                badgePool.append(badge)
            }
            for (i, badge) in badgePool.enumerated() {
                guard i < specs.count else { badge.isHidden = true; continue }
                let spec = specs[i]
                badge.isHidden = false
                badge.configure(number: spec.number, intention: spec.intention, scale: scale)
                badge.numeroAffiche = spec.number
                badge.pulser(spec.number == pulsingNumber)
                badge.anchorPoint = CGPoint(x: spec.anchorX, y: 0.5)
                // Ramené dans le cadre : une marque posée au bord de l'écran aurait son
                // numéro à moitié dehors, donc illisible — et le numéro est ce par quoi
                // l'utilisateur désigne la marque à voix haute.
                badge.position = clamp(spec.anchor, width: badge.bounds.width,
                                       anchorX: spec.anchorX)
            }
        }
    }

    /// Ramène une pastille dans les limites de la vue.
    private func clamp(_ point: CGPoint, width: CGFloat, anchorX: CGFloat) -> CGPoint {
        let half = BadgeLayer.diameter / 2
        let left = point.x - width * anchorX
        let corrected = min(max(left, 2), max(2, bounds.width - width - 2))
        return CGPoint(x: corrected + width * anchorX,
                       y: min(max(point.y, half + 2), bounds.height - half - 2))
    }

    func clear() {
        transaction {
            live.setPaths([:])
            committed.setPaths([:])
            for badge in badgePool { badge.isHidden = true }
        }
    }
}

/// Un numéro à poser, avec son point d'ancrage local.
struct BadgeSpec: Equatable {
    let number: Int
    let anchor: CGPoint
    /// Côté par lequel la gélule s'accroche : 0 pour s'étendre vers la droite, 1 vers la
    /// gauche, 0,5 pour rester centrée. Sans lui, un libellé long partirait du mauvais
    /// côté et recouvrirait ce que la marque désigne.
    let anchorX: CGFloat
    /// Libellé d'intention, `nil` tant qu'aucune n'est choisie (S23).
    let intention: String?
}

/// Style de l'encre — spécification § 5.6.
///
/// Le vermillon est constant d'un rapport à l'autre : un agent qui voit toujours la même
/// couleur de repère n'a pas à deviner ce qui est une annotation et ce qui appartient à
/// l'interface testée.
enum InkStyle {
    static let color = NSColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)  // #FF3B30
    static let width: CGFloat = 3

    /// Opacité du surlignage. Assez pour se voir sur un fond blanc comme sur un fond
    /// sombre, assez peu pour que le texte surligné reste lisible dans la capture — sans
    /// quoi le surlignage effacerait ce qu'il désigne.
    static let washColor = color.withAlphaComponent(0.22)
}
