import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// Rendu de l'encre — spécification § 6.4
//
// Trois couches, pour que le trait en cours ne force pas la recomposition de ce qui est
// déjà posé :
//
//   committed  les traits terminés, rasterisés — coût de recomposition nul
//   live       le trait en cours, un SEUL CAShapeLayer
//   badges     les numéros (S21 et S23)
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

    private let committed = CAShapeLayer()
    private let live = CAShapeLayer()
    private let badges = CALayer()

    /// Rendu gelé : le panneau est masqué, commiter ne servirait à rien.
    private(set) var isFrozen = false

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

        for l in [committed, live] {
            l.fillColor = nil
            l.strokeColor = InkStyle.color.cgColor
            l.lineWidth = InkStyle.width
            l.lineCap = .round
            l.lineJoin = .round
            // Aucune ombre, aucun flou, aucun `NSVisualEffectView` : chacun est une
            // passe de composition supplémentaire, et le risque R8 en fait un danger
            // explicite — l'outil deviendrait la lenteur qu'il sert à diagnostiquer.
            l.shadowOpacity = 0
            l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
        }

        // Les traits posés ne changent plus : les rasteriser rend leur recomposition
        // gratuite pendant que le trait vivant se redessine à chaque frame.
        committed.shouldRasterize = true
        committed.rasterizationScale = window?.backingScaleFactor ?? 2.0

        root.addSublayer(committed)
        root.addSublayer(live)
        root.addSublayer(badges)
        layoutLayers()
    }

    func layoutLayers() {
        guard let root = layer else { return }
        transaction {
            for l in [committed, live, badges] { l.frame = root.bounds }
            committed.rasterizationScale = window?.backingScaleFactor ?? 2.0
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        committed.rasterizationScale = window?.backingScaleFactor ?? 2.0
    }

    /// Une transaction sans animation implicite. Tout passe par ici.
    private func transaction(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - Gel sur occlusion (S18)

    func setFrozen(_ frozen: Bool) {
        guard frozen != isFrozen else { return }
        isFrozen = frozen
    }

    // MARK: - Contenu

    /// Publie le trait en cours.
    func setLivePath(_ path: CGPath?) {
        guard !isFrozen else { return }
        transaction { live.path = path }
    }

    /// Publie l'ensemble des traits posés.
    func setCommittedPath(_ path: CGPath?) {
        guard !isFrozen else { return }
        transaction { committed.path = path }
    }

    func clear() {
        transaction {
            live.path = nil
            committed.path = nil
            badges.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }
}

/// Style de l'encre — spécification § 5.6.
///
/// Le vermillon est constant d'un rapport à l'autre : un agent qui voit toujours la même
/// couleur de repère n'a pas à deviner ce qui est une annotation et ce qui appartient à
/// l'interface testée.
enum InkStyle {
    static let color = NSColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)  // #FF3B30
    static let width: CGFloat = 3
}
