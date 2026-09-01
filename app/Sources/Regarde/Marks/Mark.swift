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

    /// Depuis un point local à une vue de taille donnée, RAMENÉ dans le cadre.
    ///
    /// Un geste qui sort de l'écran de départ produirait sinon des coordonnées hors de
    /// [0, 1] : le calque les clippe à l'affichage, mais elles ressortent telles quelles
    /// dans la géométrie de la marque. Relevé dans un journal réel —
    /// `bbox (0.679, -0.085) 0.049×0.603` — et le recadrage qui en découle vise alors une
    /// zone en partie hors de l'image, donc décalée.
    ///
    /// La marque décrit ce qui est VISIBLE : c'est ce que l'utilisateur a désigné, et
    /// c'est tout ce que la capture pourra montrer.
    init(local: CGPoint, in size: CGSize) {
        x = size.width > 0 ? min(max(Double(local.x / size.width), 0), 1) : 0
        y = size.height > 0 ? min(max(Double(local.y / size.height), 0), 1) : 0
    }

    /// Vers un point local à une vue de taille donnée.
    func local(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }
}

/// Rectangle normalisé.
struct NormRect: Codable, Hashable, Sendable {
    var x, y, w, h: Double

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

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
    /// Une note ancrée à un point (S70, § 3.4) : le mode silencieux du § 7.4.
    /// Le texte est saisi APRÈS la pose de l'ancre, et la marque n'existe
    /// vraiment qu'une fois validée — c'est pourquoi il est mutable ici.
    case text(NormPoint, String)

    var points: [NormPoint] {
        switch self {
        case .arrow(let a, let b): [a, b]
        case .point(let p): [p]
        case .text(let p, _): [p]
        case .rect(let r), .highlight(let r):
            [NormPoint(x: r.x, y: r.y), NormPoint(x: r.x + r.w, y: r.y + r.h)]
        }
    }

    var boundingBox: NormRect { NormRect(bounding: points) }

    /// Ce sur quoi le recadrage doit se centrer — qui n'est pas toujours la forme.
    ///
    /// Une flèche est un CHEMIN vers son sujet, pas le sujet. Centrer sur sa boîte
    /// englobante met le milieu du trait au centre de l'image et laisse ce qu'elle
    /// désigne sur un bord, souvent coupé. L'agent reçoit alors un gros plan sur du vide
    /// traversé par un trait.
    ///
    /// La zone retenue est donc un carré autour de la POINTE, dimensionné sur la
    /// longueur de la flèche : un geste ample désigne une zone, un geste court désigne un
    /// détail, et la dilatation qui suit rend visible une bonne part du trait dans les
    /// deux cas.
    ///
    /// Les formes fermées, elles, sont leur propre sujet : ce qu'on encadre est ce dont
    /// on parle.
    var focusBox: NormRect {
        switch self {
        case .arrow(let from, let to):
            let dx = to.x - from.x, dy = to.y - from.y
            let length = (dx * dx + dy * dy).squareRoot()
            // 22 % de la longueur, avec un plancher : une flèche minuscule ne doit pas
            // produire une zone d'intérêt de quelques pixels.
            let half = max(length * 0.22, 0.010)
            return NormRect(x: to.x - half, y: to.y - half, w: half * 2, h: half * 2)
        case .point, .rect, .highlight:
            return boundingBox
        case .text(let p, _):
            // Une note désigne ce qu'elle touche, pas la note elle-même : la
            // zone d'intérêt est un carré autour de l'ancre, comme pour la
            // pointe d'une flèche.
            return NormRect(x: p.x - 0.03, y: p.y - 0.03, w: 0.06, h: 0.06)
        }
    }

    /// Comment la forme est peinte.
    ///
    /// Le découpage n'est pas cosmétique : un surlignage tracé au trait donne un cadre
    /// vide, et un point tracé au trait donne un anneau. Chacun ferait un repère
    /// différent de celui que l'utilisateur croit poser.
    var rendering: MarkRendering {
        switch self {
        case .arrow, .rect: .stroke
        case .point, .text: .fill
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
    case arrow, rect, point, highlight, text

    var label: String {
        switch self {
        case .arrow: "flèche"
        case .rect: "cadre"
        case .point: "point"
        case .highlight: "surlignage"
        case .text: "texte"
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
        case .text: "t"
        }
    }

    /// Ordre stable, utilisé pour indexer le cache de codes du tap.
    var slot: Int {
        switch self {
        case .arrow: 0
        case .rect: 1
        case .point: 2
        case .highlight: 3
        case .text: 4
        }
    }

    static func at(slot: Int) -> MarkTool? {
        switch slot {
        case 0: .arrow
        case 1: .rect
        case 2: .point
        case 3: .highlight
        case 4: .text
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
    /// Mutable pour la seule note texte (S70) : l'ancre est posée au geste, le
    /// texte à la frappe. Toutes les autres formes naissent complètes.
    var shape: MarkShape
    let tool: MarkTool
    /// Application annotée au moment du tracé.
    ///
    /// Hors session, la cible SUIT l'application au premier plan : une rafale peut donc
    /// porter sur plusieurs applications sans que l'utilisateur s'en aperçoive — observé
    /// en vrai, cinq marques réparties entre deux d'entre elles dans un seul dossier.
    /// Sans cette information, le rapport du lot 3 attribuerait le tout à une seule.
    let target: String?
    /// Étiquette posée après coup, `⌥⌘ + 1..6`. Reste `nil` si l'utilisateur n'en pose
    /// pas : en mode parlé, l'intention est dans la voix, pas au clavier.
    var intention: Intention?

    /// Instant du `mouseDown`, sur la timeline de session.
    ///
    /// Le `mouseDown` et non le relâchement, et c'est la même raison qui fixe le
    /// numéro là ([ADR-0013](adr/0013)) : c'est l'instant que l'utilisateur DÉSIGNE.
    /// Entre la pression et le relâchement il s'écoule le temps d'un geste — une
    /// seconde, parfois deux — pendant lequel l'infobulle s'est refermée et
    /// l'animation s'est terminée. Apparier sur le relâchement donnerait l'écran
    /// d'après, ce qui est exactement le bug B1 sous un autre nom.
    let t: SessionTime
    /// D'où vient `t` : de l'horodatage matériel de l'événement, ou d'un repli.
    ///
    /// Publié dans le journal parce qu'un repli n'est pas une erreur mais une
    /// PERTE DE PRÉCISION, et qu'elle doit se voir avant qu'on s'étonne d'un
    /// appariement flou. Les événements synthétiques — Karabiner, pilotes de souris
    /// tiers, Universal Control — empruntent ce chemin (C12).
    let timeOrigin: TimestampOrigin

    /// Segment de capture porteur, s'il y en a un.
    ///
    /// **Optionnel, et c'est un cas légitime, pas une lacune.** Le mode éclair —
    /// le mode MAJORITAIRE — n'ouvre ni session, ni flux, ni segment : sa marque
    /// est servie par le filet RAM et n'a aucun segment auquel se rapporter. Le
    /// rendre obligatoire aurait forcé un segment factice, c'est-à-dire un
    /// mensonge dans le manifeste.
    var segmentID: CaptureSegmentID?
    /// Marque posée à T−N par `⌥⌘ + 1..9`, et non au geste (§ 5.1).
    var isRetroactive: Bool = false
    /// D'où vient son image. `preRoll` signale une résolution réduite.
    var imageSource: ImageSource = .aucune
    /// Numéro de la demande d'instantané déposée par le tap à la PRESSION (S37).
    ///
    /// Zéro quand l'anneau n'était pas armé — première marque d'une session, écran
    /// figé — auquel cas le filet RAM prend le relais. C'est la clé qui relie, au
    /// relâchement, la marque à la frame prise une seconde plus tôt.
    var snapshot: UInt64 = 0

    init(id: UUID = UUID(), number: Int, displayID: CGDirectDisplayID,
         shape: MarkShape, tool: MarkTool, target: String? = nil,
         intention: Intention? = nil,
         t: SessionTime = SessionTime(seconds: 0),
         timeOrigin: TimestampOrigin = .fallbackNow,
         segmentID: CaptureSegmentID? = nil,
         isRetroactive: Bool = false,
         imageSource: ImageSource = .aucune,
         snapshot: UInt64 = 0) {
        self.id = id
        self.number = number
        self.displayID = displayID
        self.shape = shape
        self.tool = tool
        self.target = target
        self.intention = intention
        self.t = t
        self.timeOrigin = timeOrigin
        self.segmentID = segmentID
        self.isRetroactive = isRetroactive
        self.imageSource = imageSource
        self.snapshot = snapshot
    }
}
