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
        /// Facteur appliqué après le prélèvement.
        let scale: CGFloat

        /// Taille de l'image finale.
        var outputSize: CGSize {
            CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
        }

        /// Point normalisé écran → point du contexte de dessin (origine en bas à gauche).
        func point(_ p: NormPoint) -> CGPoint {
            let xCapture = CGFloat(p.x) * captureSize.width
            let yCaptureBottom = CGFloat(p.y) * captureSize.height
            // `sourceRect` compte depuis le haut : son bord bas en repère bas-gauche est
            // à `captureH - maxY`.
            let originBottom = captureSize.height - sourceRect.maxY
            return CGPoint(x: (xCapture - sourceRect.minX) * scale,
                           y: (yCaptureBottom - originBottom) * scale)
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
    static let haloDark = CGColor(srgbRed: 0.043, green: 0.043, blue: 0.051, alpha: 0.70)
    static let haloLight = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.80)

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
            let rect = place(number: item.number, intention: item.intention,
                             around: box, in: CGSize(width: w, height: h),
                             avoiding: placed, map: map, frame: frame, longSide: longSide,
                             focus: designated(item.shape, frame: frame))
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
            // Le halo est tracé À DEUX FOIS l'épaisseur de l'encre, donc il déborde d'une
            // demi-épaisseur de chaque côté. C'est assez pour détacher le trait d'un fond
            // de couleur voisine, sans l'épaissir au point de masquer ce qu'il désigne.
            ctx.setStrokeColor(halo)
            ctx.setLineWidth(width * 2)
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
            ctx.setLineWidth(width * 1.6)
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

    /// Huit positions candidates autour de la boîte, filtrées puis départagées.
    ///
    /// Trois contraintes dures : rester dans l'image, ne recouvrir aucun badge déjà posé,
    /// et **s'écarter du point que la marque désigne**. Cette troisième contrainte a été
    /// ajoutée après la première gravure de contrôle, où le badge s'était posé du côté de
    /// la POINTE d'une flèche — le seul endroit qu'elle sert à montrer. Le fond y était
    /// le plus uni, ce qui est exactement ce qu'on demandait à l'algorithme ; on lui
    /// demandait la mauvaise chose.
    ///
    /// Le départage entre les positions restantes se fait sur la variance locale de
    /// luminance : un chiffre posé sur du texte se lit mal quelle que soit sa couleur.
    static func place(number: Int, intention: String?, around box: CGRect, in size: CGSize,
                      avoiding placed: [CGRect], map: LuminanceMap?, frame: Frame,
                      longSide: CGFloat, focus: CGPoint? = nil) -> CGRect {
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

        func evaluate(respectingFocus: Bool) -> CGRect? {
            var best: (rect: CGRect, score: Float)?
            for centre in candidates {
                let rect = CGRect(x: centre.x - hw, y: centre.y - hh,
                                  width: badge.width, height: badge.height)
                guard rect.minX >= 0, rect.minY >= 0,
                      rect.maxX <= size.width, rect.maxY <= size.height else { continue }
                guard !placed.contains(where: { $0.intersects(rect) }) else { continue }
                if respectingFocus, let focus,
                   hypot(rect.midX - focus.x, rect.midY - focus.y) < keepClear { continue }

                let variance = map?.stats(in: frame.flipped(rect))?.variance ?? 0
                if best == nil || variance < best!.score { best = (rect, variance) }
            }
            return best?.rect
        }

        // La contrainte d'écart est RELÂCHÉE si elle ne laisse rien : mieux vaut un badge
        // près de la pointe qu'un badge rabattu dans un coin, sans rapport avec sa marque.
        if let rect = evaluate(respectingFocus: true) { return rect }
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
