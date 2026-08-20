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

    private let label = CATextLayer()

    /// Diamètre de la pastille. Assez grand pour rester lisible après le recadrage du
    /// lot 2, qui peut réduire l'image.
    static let diameter: CGFloat = 22

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
        label.fontSize = 13
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
    private static var font: NSFont { .systemFont(ofSize: 13, weight: .semibold) }

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
