import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Modèle d'une marque — spécification § 3.4
//
// La géométrie est stockée en coordonnées NORMALISÉES, entre 0 et 1 dans le cadre de
// l'écran porteur. C'est ce qui la rend indépendante de la résolution : un changement
// d'échelle à chaud, un écran rebranché à une autre définition, une capture à la
// résolution native — la marque reste au même endroit de l'image.
//
// Stocker des points aurait suffi au lot 2. Ce serait faux au lot 3, quand la marque
// devra pointer un pixel dans une frame dont le `contentRect` peut différer du cadre
// de l'écran (§ 3.3), et le rattrapage coûterait une reprise du modèle.
// ─────────────────────────────────────────────────────────────────────────────

/// Point normalisé, entre 0 et 1 dans le cadre de référence.
struct NormPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Depuis un point local à une vue de taille donnée.
    init(local: CGPoint, in size: CGSize) {
        x = size.width > 0 ? Double(local.x / size.width) : 0
        y = size.height > 0 ? Double(local.y / size.height) : 0
    }

    /// Vers un point local à une vue de taille donnée.
    func local(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }
}

/// Rectangle normalisé.
struct NormRect: Codable, Hashable, Sendable {
    var x, y, w, h: Double

    func local(in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height,
               width: CGFloat(w) * size.width, height: CGFloat(h) * size.height)
    }

    /// Boîte englobante d'une suite de points.
    init(bounding points: [NormPoint]) {
        guard let first = points.first else { x = 0; y = 0; w = 0; h = 0; return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        x = minX; y = minY; w = maxX - minX; h = maxY - minY
    }
}

/// Forme d'une marque. Seule la flèche existe en S19 ; les autres arrivent en S20.
enum MarkShape: Codable, Hashable, Sendable {
    case arrow(from: NormPoint, to: NormPoint)
    case rect(NormRect)
    case point(NormPoint)
    case highlight(NormRect)

    var points: [NormPoint] {
        switch self {
        case .arrow(let a, let b): [a, b]
        case .point(let p): [p]
        case .rect(let r), .highlight(let r):
            [NormPoint(x: r.x, y: r.y), NormPoint(x: r.x + r.w, y: r.y + r.h)]
        }
    }

    var boundingBox: NormRect { NormRect(bounding: points) }

    /// Comment la forme est peinte.
    ///
    /// Le découpage n'est pas cosmétique : un surlignage tracé au trait donne un cadre
    /// vide, et un point tracé au trait donne un anneau. Chacun ferait un repère
    /// différent de celui que l'utilisateur croit poser.
    var rendering: MarkRendering {
        switch self {
        case .arrow, .rect: .stroke
        case .point: .fill
        case .highlight: .wash
        }
    }
}

/// Peinture d'une forme.
enum MarkRendering: Sendable {
    /// Trait vermillon opaque — flèche, cadre.
    case stroke
    /// Aplat vermillon opaque — point.
    case fill
    /// Aplat translucide, qui laisse lire l'interface dessous — surlignage.
    case wash
}

/// Outil actif. Le changement se fait au clavier, ⌥⌘ tenu.
enum MarkTool: String, CaseIterable, Sendable {
    case arrow, rect, point, highlight

    var label: String {
        switch self {
        case .arrow: "flèche"
        case .rect: "cadre"
        case .point: "point"
        case .highlight: "surlignage"
        }
    }

    /// Touche de sélection, désignée par son CARACTÈRE et non par un code physique.
    ///
    /// Le lot 0 l'a payé : coder un code physique fait migrer le raccourci d'une touche
    /// à l'autre sur un clavier non-QWERTY. Ici la règle vaut d'autant plus que les
    /// initiales sont françaises — Flèche, Cadre, Point, Surlignage.
    var key: Character {
        switch self {
        case .arrow: "f"
        case .rect: "c"
        case .point: "p"
        case .highlight: "s"
        }
    }

    /// Ordre stable, utilisé pour indexer le cache de codes du tap.
    var slot: Int {
        switch self {
        case .arrow: 0
        case .rect: 1
        case .point: 2
        case .highlight: 3
        }
    }

    static func at(slot: Int) -> MarkTool? {
        switch slot {
        case 0: .arrow
        case 1: .rect
        case 2: .point
        case 3: .highlight
        default: nil
        }
    }
}

/// Une marque posée.
struct Mark: Identifiable, Sendable {
    let id: UUID
    /// Numéro attribué au `mouseDown`, DÉFINITIF (ADR-0013).
    ///
    /// L'utilisateur prononce les numéros à voix haute — « comme sur la marque 2 » —
    /// donc toute renumérotation ultérieure rendrait le rapport incohérent avec ce qui
    /// a été dit. Une marque supprimée laisse un trou. Numérotation effective en S21.
    let number: Int
    /// Écran porteur : sans lui, une marque n'est plus interprétable après un
    /// changement de disposition.
    let displayID: CGDirectDisplayID
    let shape: MarkShape
    let tool: MarkTool
    /// Étiquette posée après coup, `⌥⌘ + 1..6`. Reste `nil` si l'utilisateur n'en pose
    /// pas : en mode parlé, l'intention est dans la voix, pas au clavier.
    var intention: Intention?

    init(id: UUID = UUID(), number: Int, displayID: CGDirectDisplayID,
         shape: MarkShape, tool: MarkTool, intention: Intention? = nil) {
        self.id = id
        self.number = number
        self.displayID = displayID
        self.shape = shape
        self.tool = tool
        self.intention = intention
    }
}
