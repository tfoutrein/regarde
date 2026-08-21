import AppKit
import CoreGraphics
import CoreText
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Gravure des marques dans l'image — S26, spécification § 9.2
//
// La gravure a lieu APRÈS le redimensionnement, jamais avant. Graver d'abord puis
// réduire divise l'épaisseur du trait par le même facteur : sur un recadrage réduit de
// moitié, un trait de 3 px en fait 1,5 et disparaît à la première compression. Les
// dimensions de l'encre se calculent donc sur l'image FINALE, celle que l'agent verra.
//
// Le halo n'est pas décoratif. L'encre vermillon a un contraste médiocre sur un fond
// rouge, orange ou simplement sombre ; sans halo, une flèche sur une barre d'erreur
// rouge devient invisible — précisément le cas où l'utilisateur annote.
//
// Formes d'abord, badges ensuite, dans cet ordre strict : un numéro recouvert par un
// tracé postérieur ne se lit plus, et le numéro est ce par quoi l'utilisateur a désigné
// la marque à voix haute.
// ─────────────────────────────────────────────────────────────────────────────

enum Engraver {

    /// Une marque à graver, déjà rapportée au repère de l'image finale.
    struct Item {
        let number: Int
        let shape: MarkShape
        let intention: String?
    }

    /// Transformation du repère du modèle vers celui de l'image gravée.
    ///
    /// Le modèle stocke des coordonnées normalisées dans le cadre de l'ÉCRAN, origine en
    /// bas à gauche (§ 3.4). L'image, elle, est un recadrage exprimé en pixels avec une
    /// origine en haut à gauche, puis éventuellement réduit. Trois conversions donc, et
    /// elles sont rassemblées ici plutôt que dispersées : une inversion d'axe oubliée
    /// produit un tracé juste en haut de l'écran et faux en bas, donc juste une fois sur
    /// deux — le pire des symptômes à diagnostiquer.
    struct Frame: Sendable {
        /// Dimensions de la capture entière, en pixels.
        let captureSize: CGSize
        /// Rectangle prélevé, en pixels, origine en HAUT à gauche.
        let sourceRect: CGRect
        /// Facteurs appliqués après le prélèvement, un par axe.
        ///
        /// Deux et non un : l'alignement sur la tuile de facturation et l'arrondi entier
        /// du prélèvement ne tombent pas juste en même temps, et reporter tout l'écart
        /// sur un seul axe décale la gravure.
        let scaleX: CGFloat
        let scaleY: CGFloat

        init(captureSize: CGSize, sourceRect: CGRect,
             scaleX: CGFloat, scaleY: CGFloat) {
            self.captureSize = captureSize
            self.sourceRect = sourceRect
            self.scaleX = scaleX
            self.scaleY = scaleY
        }

        init(captureSize: CGSize, sourceRect: CGRect, scale: CGFloat) {
            self.init(captureSize: captureSize, sourceRect: sourceRect,
                      scaleX: scale, scaleY: scale)
        }

        /// Taille de l'image finale.
        var outputSize: CGSize {
            CGSize(width: sourceRect.width * scaleX, height: sourceRect.height * scaleY)
        }

        /// Point normalisé écran → point du contexte de dessin (origine en bas à gauche).
        func point(_ p: NormPoint) -> CGPoint {
            let xCapture = CGFloat(p.x) * captureSize.width
            let yCaptureBottom = CGFloat(p.y) * captureSize.height
            // `sourceRect` compte depuis le haut : son bord bas en repère bas-gauche est
            // à `captureH - maxY`.
            let originBottom = captureSize.height - sourceRect.maxY
            return CGPoint(x: (xCapture - sourceRect.minX) * scaleX,
                           y: (yCaptureBottom - originBottom) * scaleY)
        }

        func rect(_ r: NormRect) -> CGRect {
            let a = point(NormPoint(x: r.x, y: r.y))
            let b = point(NormPoint(x: r.x + r.w, y: r.y + r.h))
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        }

        /// Bascule un point du contexte (bas-gauche) vers le repère de `LuminanceMap`
        /// (haut-gauche).
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: outputSize.height - rect.maxY,
                   width: rect.width, height: rect.height)
        }
    }

    // MARK: - Dimensions, calculées sur l'image finale

    /// Épaisseur du trait : `max(3 px, 0,22 % du côté long)`.
    static func inkWidth(longSide: CGFloat) -> CGFloat { max(3, longSide * 0.0022) }

    /// Diamètre du badge : `max(26 px, 2,2 % du côté long)`.
    static func badgeDiameter(longSide: CGFloat) -> CGFloat { max(26, longSide * 0.022) }

    static let ink = CGColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    static let washAlpha: CGFloat = 0.22

    /// Seuil de bascule du halo, en L*. Au-dessus, le fond est clair et le halo doit être
    /// sombre ; au-dessous, l'inverse.
    static let haloThreshold: Float = 55
    static let haloDark = CGColor(srgbRed: 0.043, green: 0.043, blue: 0.051, alpha: 0.50)
    static let haloLight = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.75)

    /// Débordement du halo, en multiples de l'épaisseur du trait.
    ///
    /// 1,5 et non 2 : le halo était le vrai responsable de l'épaisseur perçue. Le trait
    /// gravé fait la même épaisseur qu'à l'écran, mais un halo à deux fois cette largeur
    /// le triplait à l'œil — au point qu'un cadre fin tracé à quelques pixels d'un
    /// paragraphe ressortait épais et collé au texte. Rapporté au premier usage réel.
    static let haloSpread: CGFloat = 1.5

    // MARK: - Gravure

    static func engrave(_ image: CGImage, items: [Item], frame: Frame) -> CGImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0, !items.isEmpty else { return image }

        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let longSide = CGFloat(max(w, h))
        let width = inkWidth(longSide: longSide)
        let map = LuminanceMap(image)

        // Formes d'abord.
        for item in items {
            draw(item.shape, in: ctx, frame: frame, width: width, map: map)
        }

        // Badges ensuite, en mémorisant les positions déjà prises : deux marques voisines
        // ne doivent pas superposer leurs numéros.
        var placed: [CGRect] = []
        for item in items {
            let box = boundingRect(of: item.shape, frame: frame)
            // L'écart est proportionné au badge, donc à l'image : 14 points à l'écran
            // n'ont pas la même signification dans un recadrage de 896 px.
            let preferred = MarkGeometry.badgeAnchor(
                for: item.shape, offset: badgeDiameter(longSide: longSide) * 0.64,
                project: { frame.point($0) })
            let rect = place(number: item.number, intention: item.intention,
                             around: box, in: CGSize(width: w, height: h),
                             avoiding: placed, map: map, frame: frame, longSide: longSide,
                             focus: designated(item.shape, frame: frame),
                             preferred: preferred)
            drawBadge(number: item.number, intention: item.intention, in: rect, ctx: ctx,
                      longSide: longSide)
            placed.append(rect)
        }

        return ctx.makeImage() ?? image
    }

    // MARK: - Formes

    private static func draw(_ shape: MarkShape, in ctx: CGContext, frame: Frame,
                             width: CGFloat, map: LuminanceMap?) {
        let path = shapePath(shape, frame: frame, width: width)
        let halo = haloColor(for: shape, frame: frame, map: map, width: width)

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch shape.rendering {
        case .stroke:
            // Le halo déborde d'un quart d'épaisseur de chaque côté : assez pour détacher
            // le trait d'un fond de couleur voisine, trop peu pour l'épaissir à l'œil.
            ctx.setStrokeColor(halo)
            ctx.setLineWidth(width * haloSpread)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.setStrokeColor(ink)
            ctx.setLineWidth(width)
            ctx.addPath(path)
            ctx.strokePath()

        case .fill:
            ctx.setStrokeColor(halo)
            ctx.setLineWidth(width)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.setFillColor(ink)
            ctx.addPath(path)
            ctx.fillPath()

        case .wash:
            ctx.setFillColor(ink.copy(alpha: washAlpha) ?? ink)
            ctx.addPath(path)
            ctx.fillPath()

            // Le lavis porte un liseré à pleine opacité : sans lui, un surlignage sur un
            // fond clair devient un halo aux bords indécis, et l'agent ne peut pas dire
            // où commence la zone désignée.
            ctx.setStrokeColor(halo)
            ctx.setLineWidth(width * 1.3)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.setStrokeColor(ink)
            ctx.setLineWidth(width * 0.8)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Chemin d'une forme dans le repère de l'image.
    ///
    /// Réutilise `MarkGeometry`, la même fonction que le calque à l'écran. Deux
    /// implémentations parallèles finiraient par diverger, et l'agent verrait une flèche
    /// différente de celle que l'utilisateur a tracée.
    static func shapePath(_ shape: MarkShape, frame: Frame, width: CGFloat) -> CGPath {
        switch shape {
        case .arrow(let a, let b):
            return MarkGeometry.arrowPath(from: frame.point(a), to: frame.point(b),
                                          lineWidth: width)
        case .rect(let r), .highlight(let r):
            return CGPath(rect: frame.rect(r), transform: nil)
        case .point(let p):
            return MarkGeometry.pointPath(at: frame.point(p), lineWidth: width)
        }
    }

    static func boundingRect(of shape: MarkShape, frame: Frame) -> CGRect {
        frame.rect(shape.boundingBox)
    }

    /// Le point que la marque DÉSIGNE, à ne pas recouvrir.
    ///
    /// Pour une flèche, c'est la pointe et rien d'autre : le reste du trait n'est qu'un
    /// chemin pour y arriver. Pour un point, c'est le point. Pour les formes fermées, le
    /// contenu est à l'intérieur, et le badge se range de toute façon dehors — aucune
    /// exclusion supplémentaire n'est nécessaire.
    static func designated(_ shape: MarkShape, frame: Frame) -> CGPoint? {
        switch shape {
        case .arrow(_, let to): frame.point(to)
        case .point(let p): frame.point(p)
        case .rect, .highlight: nil
        }
    }

    /// Couleur du halo, décidée sur la luminance du fond SOUS le tracé.
    ///
    /// La mesure porte sur la boîte du tracé dilatée, et non sur toute l'image : une
    /// capture majoritairement claire avec une barre sombre à l'endroit annoté donnerait
    /// un halo clair sur fond sombre, soit l'inverse de ce qu'il faut.
    static func haloColor(for shape: MarkShape, frame: Frame, map: LuminanceMap?,
                          width: CGFloat) -> CGColor {
        guard let map else { return haloDark }
        let box = boundingRect(of: shape, frame: frame).insetBy(dx: -width * 3, dy: -width * 3)
        guard let stats = map.stats(in: frame.flipped(box)) else { return haloDark }
        return stats.mean > haloThreshold ? haloDark : haloLight
    }

    // MARK: - Badges

    /// La position du calque d'abord, huit positions de repli ensuite.
    ///
    /// **L'ordre est le point important.** La position préférée est exactement celle que
    /// le calque a affichée pendant le tracé : à la queue de la flèche, au coin d'un
    /// cadre. Tant qu'elle tient dans l'image et ne recouvre rien, c'est elle qui est
    /// retenue — donc l'image reproduit ce que l'utilisateur a vu en traçant.
    ///
    /// Les huit candidates ne servent que lorsque cette position ne marche pas : marque
    /// au bord de l'image, ou deux badges qui se chevauchent. Elles sont alors départagées
    /// sur la variance locale de luminance, parce qu'un chiffre posé sur du texte se lit
    /// mal quelle que soit sa couleur.
    ///
    /// Cet ordre a été inversé jusqu'à ce que l'auteur compare son écran et ses PNG : la
    /// variance décidait d'abord, et le numéro sautait d'un côté à l'autre entre les deux.
    /// Un outil dont on ne peut pas prévoir la sortie en la regardant ne sert pas à
    /// désigner.
    static func place(number: Int, intention: String?, around box: CGRect, in size: CGSize,
                      avoiding placed: [CGRect], map: LuminanceMap?, frame: Frame,
                      longSide: CGFloat, focus: CGPoint? = nil,
                      preferred: (point: CGPoint, anchorX: CGFloat)? = nil) -> CGRect {
        // Les positions candidates s'appuient sur la partie VISIBLE de la forme.
        //
        // Depuis que le recadrage se centre sur ce que la marque désigne, une flèche
        // longue entre dans l'image par un coin : sa boîte englobante est en grande partie
        // dehors, et des candidates calculées dessus sortent presque toutes du cadre. Le
        // repli tombait alors sur la seule qui restait — juste sous la pointe, c'est-à-dire
        // sur le sujet.
        let box = box.intersection(CGRect(origin: .zero, size: size)).isNull
            ? box : box.intersection(CGRect(origin: .zero, size: size))

        let badge = badgeSize(number: number, intention: intention, longSide: longSide)
        let gap = badgeDiameter(longSide: longSide) * 0.35
        let hw = badge.width / 2, hh = badge.height / 2

        let candidates: [CGPoint] = [
            CGPoint(x: box.minX + hw, y: box.maxY + gap + hh),   // au-dessus, à gauche
            CGPoint(x: box.maxX - hw, y: box.maxY + gap + hh),   // au-dessus, à droite
            CGPoint(x: box.minX - gap - hw, y: box.maxY - hh),   // à gauche, en haut
            CGPoint(x: box.maxX + gap + hw, y: box.maxY - hh),   // à droite, en haut
            CGPoint(x: box.minX - gap - hw, y: box.minY + hh),   // à gauche, en bas
            CGPoint(x: box.maxX + gap + hw, y: box.minY + hh),   // à droite, en bas
            CGPoint(x: box.minX + hw, y: box.minY - gap - hh),   // au-dessous, à gauche
            CGPoint(x: box.maxX - hw, y: box.minY - gap - hh),   // au-dessous, à droite
        ]

        // Rayon d'exclusion autour du point désigné. Une fois et demie la hauteur du
        // badge : assez pour dégager la pointe, assez peu pour ne pas éliminer les huit
        // positions d'une marque compacte.
        let keepClear = badge.height * 1.5

        func fits(_ rect: CGRect) -> Bool {
            rect.minX >= 0 && rect.minY >= 0
                && rect.maxX <= size.width && rect.maxY <= size.height
                && !placed.contains(where: { $0.intersects(rect) })
        }

        // La position du calque en PREMIER, et sans départage : si elle tient dans
        // l'image et ne recouvre aucun badge, c'est elle. L'image reproduit alors ce que
        // l'utilisateur a vu pendant son tracé, ce qui est la seule façon pour lui de
        // prévoir ce qu'il produit.
        if let preferred {
            let rect = CGRect(x: preferred.point.x - badge.width * preferred.anchorX,
                              y: preferred.point.y - hh,
                              width: badge.width, height: badge.height)
            if fits(rect) { return rect }
        }

        func evaluate(respectingFocus: Bool) -> CGRect? {
            var best: (rect: CGRect, score: Float)?
            for centre in candidates {
                let rect = CGRect(x: centre.x - hw, y: centre.y - hh,
                                  width: badge.width, height: badge.height)
                guard fits(rect) else { continue }
                if respectingFocus, let focus,
                   hypot(rect.midX - focus.x, rect.midY - focus.y) < keepClear { continue }

                let variance = map?.stats(in: frame.flipped(rect))?.variance ?? 0
                if best == nil || variance < best!.score { best = (rect, variance) }
            }
            return best?.rect
        }

        // La contrainte d'écart est RELÂCHÉE en dernier recours seulement : un badge posé
        // sur ce que la marque désigne masque le défaut à montrer, ce qui est pire qu'un
        // badge un peu loin. On essaie donc d'abord de le poser ailleurs, même sur un fond
        // chargé — d'où le second passage, qui ignore la variance et se contente de la
        // première position tenant dans l'image et dégagée du sujet.
        if let rect = evaluate(respectingFocus: true) { return rect }

        if let focus {
            // Dernier essai avant de renoncer : les huit positions autour du POINT
            // DÉSIGNÉ lui-même, écartées du rayon de dégagement. Elles existent toujours,
            // puisque le recadrage est justement centré dessus.
            let r = badge.height * 1.9
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let centre = CGPoint(x: focus.x + cos(angle) * r, y: focus.y + sin(angle) * r)
                let rect = CGRect(x: centre.x - hw, y: centre.y - hh,
                                  width: badge.width, height: badge.height)
                if fits(rect) { return rect }
            }
        }

        if let rect = evaluate(respectingFocus: false) { return rect }

        // Aucune position candidate ne convient — marque au coin de l'image, ou huit
        // badges déjà serrés autour. On rabat DANS l'image plutôt que de laisser un
        // numéro à moitié dehors : un numéro tronqué ne se lit pas, et c'est par lui que
        // l'agent retrouve la marque dans le rapport.
        let fallback = CGRect(x: box.minX, y: box.maxY + gap,
                              width: badge.width, height: badge.height)
        return CGRect(x: min(max(fallback.minX, 2), max(2, size.width - badge.width - 2)),
                      y: min(max(fallback.minY, 2), max(2, size.height - badge.height - 2)),
                      width: badge.width, height: badge.height)
    }

    static func badgeSize(number: Int, intention: String?, longSide: CGFloat) -> CGSize {
        let d = badgeDiameter(longSide: longSide)
        if let intention {
            let text = "\(number) · \(intention)"
            let width = textWidth(text, size: d * 0.62) + d * 0.9
            return CGSize(width: max(d, width), height: d)
        }
        // Capsule ×1,45 dès deux chiffres : un « 12 » dans un disque rond déborderait ou
        // devrait rétrécir la fonte au point de ne plus se lire après réduction.
        return CGSize(width: number >= 10 ? d * 1.45 : d, height: d)
    }

    private static func drawBadge(number: Int, intention: String?, in rect: CGRect,
                                  ctx: CGContext, longSide: CGFloat) {
        let d = badgeDiameter(longSide: longSide)
        ctx.saveGState()

        // Disque ou capsule plein vermillon, cerné de blanc : le cerne détache le badge
        // d'un fond rouge, où le vermillon seul se fondrait.
        let path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                          cornerHeight: rect.height / 2, transform: nil)
        ctx.setFillColor(ink)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(max(1, d * 0.06))
        ctx.addPath(path)
        ctx.strokePath()

        let text = intention.map { "\(number) · \($0)" } ?? "\(number)"
        drawText(text, in: rect, size: d * 0.62, ctx: ctx)
        ctx.restoreGState()
    }

    // MARK: - Texte

    /// SF Pro Rounded Bold, avec repli sur la fonte système grasse.
    ///
    /// Propriété calculée : `NSFont` n'est pas `Sendable`, donc Swift 6 refuse une
    /// constante globale. AppKit met les fontes en cache, la recréer ne coûte rien.
    private static func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font(size: size)])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed),
                                          nil, nil, nil)
    }

    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat,
                                 ctx: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font(size: size),
            .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        // Centrage sur la hauteur de CARACTÈRE et non sur celle de la ligne : la seconde
        // inclut les jambages, et un chiffre s'y retrouve visiblement trop haut.
        ctx.textPosition = CGPoint(x: rect.midX - width / 2,
                                   y: rect.midY - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
    }
}
