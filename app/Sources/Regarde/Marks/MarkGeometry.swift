import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Tracé des formes — S19 pour la flèche, S20 pour les autres
//
// Fonctions PURES : une forme et une taille entrent, un `CGPath` sort. Aucune
// dépendance à une vue, à un écran ou à un état.
//
// C'est ce qui permet de les réutiliser telles quelles à la gravure (S26), où le même
// tracé doit être reproduit dans une image de dimensions différentes. Une flèche
// dessinée par la vue et une autre dessinée par le graveur finiraient par diverger.
// ─────────────────────────────────────────────────────────────────────────────

enum MarkGeometry {

    /// Chemin d'une forme, dans un cadre de taille donnée.
    static func path(for shape: MarkShape, in size: CGSize, lineWidth: CGFloat) -> CGPath {
        switch shape {
        case .arrow(let from, let to):
            arrowPath(from: from.local(in: size), to: to.local(in: size), lineWidth: lineWidth)
        case .rect(let r):
            CGPath(rect: r.local(in: size), transform: nil)
        case .point(let p):
            pointPath(at: p.local(in: size), lineWidth: lineWidth)
        case .highlight(let r):
            CGPath(rect: r.local(in: size), transform: nil)
        }
    }

    // MARK: - Flèche

    /// Proportions de la pointe, relatives à l'épaisseur du trait.
    ///
    /// Relatives, et non absolues : la gravure du lot 2 redimensionne l'image, et une
    /// pointe en pixels fixes deviendrait énorme sur un recadrage serré ou invisible
    /// sur une capture pleine résolution.
    private static let headLengthFactor: CGFloat = 5.5
    private static let headHalfAngle: CGFloat = .pi / 7   // ≈ 26°

    /// Une flèche : le corps, plus deux barbes à l'extrémité.
    ///
    /// La pointe est plafonnée au tiers de la longueur du trait. Sans ce plafond, une
    /// flèche courte devient une pointe seule, illisible — et les flèches courtes sont
    /// fréquentes quand on désigne un détail.
    static func arrowPath(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)

        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        // Sous quelques pixels, l'angle n'a plus de sens : un clic sans glissement ne
        // doit pas produire une pointe orientée au hasard.
        guard length > 1 else { return path }

        let head = min(lineWidth * headLengthFactor, length / 3)
        let angle = atan2(dy, dx)

        for sign in [CGFloat(1), CGFloat(-1)] {
            let a2 = angle + .pi + sign * headHalfAngle
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x + cos(a2) * head, y: b.y + sin(a2) * head))
        }
        return path
    }

    // MARK: - Point

    /// Un point : un cercle plein, dimensionné sur l'épaisseur du trait.
    ///
    /// 2,6 fois l'épaisseur et non 1,8 : à 1,8 le disque disparaissait sous sa propre
    /// pastille de numéro sur la première capture de contrôle. Un repère qu'il faut
    /// chercher ne remplit pas son office.
    static func pointPath(at center: CGPoint, lineWidth: CGFloat) -> CGPath {
        let radius = lineWidth * 2.6
        return CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2),
                      transform: nil)
    }

    // MARK: - Ancrage du badge

    /// Où poser le numéro d'une forme, en coordonnées locales (origine en bas à gauche).
    ///
    /// Jamais sur ce que la marque désigne. La pointe d'une flèche est le pixel dont
    /// l'utilisateur parle : un badge posé dessus masquerait précisément le défaut à
    /// montrer. Le badge se range donc à la QUEUE de la flèche, et au coin supérieur
    /// gauche des formes fermées, à l'extérieur du contour.
    ///
    /// **Une seule implémentation pour l'écran et pour l'image gravée.** Le calque et la
    /// gravure ne travaillent pas dans le même repère — l'un dans le cadre de l'écran,
    /// l'autre dans un recadrage en pixels — d'où le paramètre `project`, qui est la
    /// seule chose qui les distingue.
    ///
    /// Ils avaient chacun leur règle. Le calque posait le badge à la queue, la gravure le
    /// posait là où le fond était le plus uni : le numéro sautait d'un endroit à l'autre
    /// entre ce que l'utilisateur voyait en traçant et ce qu'il retrouvait dans l'image.
    /// Un outil dont on ne peut pas prévoir la sortie en la regardant n'est pas un outil
    /// de désignation.
    static func badgeAnchor(for shape: MarkShape, offset: CGFloat,
                            project: (NormPoint) -> CGPoint) -> (point: CGPoint, anchorX: CGFloat) {
        let badgeOffset = offset
        let pointBadgeOffset = offset * 1.15

        switch shape {
        case .arrow(let from, let to):
            let a = project(from), b = project(to)
            // Reculé de quelques points au-delà de la queue, dans l'axe du trait :
            // au contact, la pastille recouvrirait le début du corps.
            let dx = a.x - b.x, dy = a.y - b.y
            let length = hypot(dx, dy)
            guard length > 1 else { return (a, 0.5) }
            let anchor = CGPoint(x: a.x + dx / length * badgeOffset,
                                 y: a.y + dy / length * badgeOffset)
            // La gélule s'étend À L'OPPOSÉ de la pointe. Une intention longue —
            // « texte à corriger » — mesure trois fois la pastille nue ; centrée, elle
            // viendrait recouvrir le corps de la flèche du côté où elle pointe.
            return (anchor, dx >= 0 ? 0 : 1)
        case .rect(let r), .highlight(let r):
            let corners = [project(NormPoint(x: r.x, y: r.y)),
                           project(NormPoint(x: r.x + r.w, y: r.y + r.h))]
            let local = CGRect(x: min(corners[0].x, corners[1].x),
                               y: min(corners[0].y, corners[1].y),
                               width: abs(corners[1].x - corners[0].x),
                               height: abs(corners[1].y - corners[0].y))
            // Ancrée par son bord gauche sur le coin, donc s'étendant vers la droite
            // au-dessus de la forme, jamais vers la gauche dans le vide.
            return (CGPoint(x: local.minX, y: local.maxY + badgeOffset), 0)
        case .point(let p):
            let local = project(p)
            return (CGPoint(x: local.x + pointBadgeOffset, y: local.y + pointBadgeOffset), 0)
        }
    }

    /// Écart du badge à l'écran, en points.
    static let screenBadgeOffset: CGFloat = 14

    /// Commodité pour le calque : la projection y est une simple mise à l'échelle.
    static func badgeAnchor(for shape: MarkShape, in size: CGSize) -> (point: CGPoint, anchorX: CGFloat) {
        badgeAnchor(for: shape, offset: screenBadgeOffset) { $0.local(in: size) }
    }

    // MARK: - Construction depuis un geste

    /// Forme produite par un glissement, selon l'outil actif.
    ///
    /// `nil` quand le geste est trop court pour porter une forme — sauf pour le point,
    /// qui est précisément fait pour un geste sans amplitude.
    static func shape(for tool: MarkTool, from a: NormPoint, to b: NormPoint,
                      in size: CGSize) -> MarkShape? {
        let localA = a.local(in: size), localB = b.local(in: size)
        let distance = hypot(localB.x - localA.x, localB.y - localA.y)

        switch tool {
        case .point:
            return .point(b)
        case .arrow:
            // Un seuil bas : 4 pt suffisent à donner une direction, et exiger davantage
            // rendrait l'outil frustrant pour désigner un détail proche.
            guard distance >= 4 else { return nil }
            return .arrow(from: a, to: b)
        case .rect, .highlight:
            let r = NormRect(bounding: [a, b])
            // Un rectangle de surface nulle ne se voit pas ; mieux vaut ne rien poser
            // que de laisser une marque invisible dans le rapport.
            guard r.w > 0.001 && r.h > 0.001 else { return nil }
            return tool == .rect ? .rect(r) : .highlight(r)
        }
    }
}
