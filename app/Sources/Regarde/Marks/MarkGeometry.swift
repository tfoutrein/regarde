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
    static func pointPath(at center: CGPoint, lineWidth: CGFloat) -> CGPath {
        let radius = lineWidth * 1.8
        return CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2),
                      transform: nil)
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
