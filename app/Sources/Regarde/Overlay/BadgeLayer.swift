import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// Le numéro d'une marque — S21, complété par l'intention en S23
//
// Une pastille vermillon pleine avec un chiffre blanc, plutôt qu'un chiffre posé sur
// l'interface. La raison est celle de la gravure (S26) : un texte sans fond devient
// illisible dès que ce qu'il survole a sa propre couleur, et l'utilisateur n'a aucun
// contrôle sur ce qu'il annote.
//
// Les pastilles sont RECYCLÉES d'une frame à l'autre. Créer un `CATextLayer` par marque
// et par frame ferait grossir l'arbre de couches au rythme du display link — invisible
// sur trois marques, mesurable sur trente.
// ─────────────────────────────────────────────────────────────────────────────

final class BadgeLayer: CALayer {
    /// Le numéro que ce calque affiche — pour retrouver le badge qui pulse.
    var numeroAffiche = 0

    /// Pulse tant que la fenêtre de parole de cette marque est ouverte (§ 2.2) :
    /// l'utilisateur voit que le micro l'écoute, sans HUD déporté.
    func pulser(_ actif: Bool) {
        if actif {
            guard animation(forKey: "pulsation") == nil else { return }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0; a.toValue = 0.45
            a.duration = 0.6; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            add(a, forKey: "pulsation")
        } else {
            removeAnimation(forKey: "pulsation")
        }
    }


    private let label = CATextLayer()

    /// Diamètre de la pastille, en POINTS. Référence unique : le graveur la reprend et la
    /// convertit à l'échelle de l'image, au lieu d'avoir sa propre formule.
    static let diameter: CGFloat = 22

    /// Corps du chiffre, en fraction du diamètre. Partagé avec la gravure pour la même
    /// raison.
    static let fontRatio: CGFloat = 13.0 / 22.0

    override init() {
        super.init()
        setup()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    private func setup() {
        bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        cornerRadius = Self.diameter / 2
        backgroundColor = InkStyle.color.cgColor
        // La bordure blanche détache la pastille d'un fond rouge ou sombre, où le
        // vermillon seul se fondrait.
        borderColor = NSColor.white.cgColor
        borderWidth = 1.5
        shadowOpacity = 0
        actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(),
                   "hidden": NSNull()]

        label.alignmentMode = .center
        label.foregroundColor = NSColor.white.cgColor
        label.fontSize = Self.diameter * Self.fontRatio
        label.font = Self.font
        label.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        addSublayer(label)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        // Centrage vertical du texte : `CATextLayer` aligne en haut, et le décalage
        // dépend de la fonte, pas d'une constante ronde.
        let height = label.fontSize * 1.2
        label.frame = CGRect(x: 0, y: (bounds.height - height) / 2,
                             width: bounds.width, height: height)
        label.contentsScale = contentsScale
    }

    /// Propriété CALCULÉE et non stockée : `NSFont` n'est pas `Sendable`, donc Swift 6
    /// refuse un `static let`. La recréer à chaque appel ne coûte rien, AppKit met les
    /// fontes en cache.
    private static var font: NSFont { .systemFont(ofSize: diameter * fontRatio, weight: .semibold) }

    /// Renseigne le contenu. Sans intention, la pastille est ronde ; avec, elle s'allonge
    /// en gélule pour porter le libellé.
    func configure(number: Int, intention: String?, scale: CGFloat) {
        contentsScale = scale
        label.contentsScale = scale

        // Le numéro d'abord, le libellé ensuite : c'est le numéro que l'utilisateur
        // prononce, et c'est par lui que l'agent retrouve la marque dans le rapport.
        let text = intention.map { "\(number) · \($0)" } ?? "\(number)"
        guard text != cachedText else { return }
        cachedText = text
        label.string = text

        // Largeur MESURÉE, jamais estimée au nombre de caractères : « ne marche pas »
        // et « lent » n'ont pas le même rapport largeur/longueur, et une gélule trop
        // courte tronquerait le libellé au milieu d'un mot.
        let width = intention == nil
            ? Self.diameter
            : (text as NSString).size(withAttributes: [.font: Self.font]).width + 18
        bounds = CGRect(x: 0, y: 0, width: max(Self.diameter, width), height: Self.diameter)
        cornerRadius = Self.diameter / 2
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Évite de reconstruire le texte et de remesurer à chaque frame du display link :
    /// le contenu d'un badge ne change qu'à la frappe d'une intention.
    private var cachedText: String?
}
