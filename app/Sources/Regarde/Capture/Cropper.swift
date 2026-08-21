import CoreGraphics
import CoreImage
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Recadrage autour d'une marque — S25, spécification § 9.2
//
// Le recadrage est le levier de coût numéro un du produit : 513 jetons contre 4 784 pour
// une capture pleine. Sa géométrie n'est donc pas une préférence esthétique, elle est
// dictée par la façon dont un modèle facture une image — par tuiles de 28 pixels.
//
// Trois règles, chacune payée par un défaut qu'elle évite :
//
//   dilatation ×2,5   une bbox serrée sur le tracé montre le défaut sans son contexte.
//                     « Ce bouton est mal aligné » n'a de sens qu'avec ce à quoi il est
//                     censé s'aligner dans le cadre.
//   alignement 28     les dimensions sont arrondies à des multiples de 28 parce que
//                     c'est la taille de tuile ; 757 pixels de large coûtent autant que
//                     784 et rendent moins.
//   Lanczos           jamais d'interpolation linéaire. La réduction est l'endroit exact
//                     où le détail annoté se perd, et c'est le seul détail qui compte.
//
// Au-delà de 40 % de la surface de l'écran, le recadrage ne fait plus économiser assez
// pour justifier la perte de contexte : on bascule sur l'image entière.
// ─────────────────────────────────────────────────────────────────────────────

enum Cropper {

    /// Taille de tuile de facturation. Toute dimension y est alignée.
    static let tile = 28

    /// Facteur de dilatation de la boîte englobante.
    static let dilation: CGFloat = 2.5

    /// Bornes du côté long de l'image écrite, en pixels.
    ///
    /// La borne haute était 896, reprise de la spécification. Elle a été écrite avant
    /// d'avoir vu un résultat, et elle écrasait les zones plates sans rien économiser :
    /// un cadre tracé autour d'un paragraphe sortait en 896×112, soit **128 tuiles** de
    /// facturation quand le palier standard en autorise 1568. Le texte y était réduit au
    /// quart de sa taille native — illisible — pour un dixième du budget disponible.
    ///
    /// C'est la SURFACE qui coûte, pas le côté long. La borne haute passe donc à 1792 px
    /// et le vrai frein devient le budget de tuiles ci-dessous.
    static let longSideRange: ClosedRange<CGFloat> = 640...1792

    /// Budget de tuiles d'un recadrage.
    ///
    /// 1024 est exactement ce qu'occupait une image carrée de 896 px sous l'ancienne
    /// règle : les recadrages compacts gardent donc leur coût, seules les zones plates ou
    /// allongées gagnent la place qu'elles laissaient perdue.
    static let cropTileBudget: CGFloat = 1024

    /// Au-delà, l'image entière coûte moins cher en contexte perdu qu'en jetons gagnés.
    static let fullThreshold: CGFloat = 0.40

    /// Réduction maximale tolérée avant que le sujet ne devienne illisible.
    ///
    /// Sur un écran Retina, un facteur de 0,5 rend exactement la densité que l'utilisateur
    /// a sous les yeux : le texte de l'image est lisible comme il l'était à l'écran.
    /// En dessous, il devient plus petit que ce qu'il regardait — et l'agent reçoit une
    /// bouillie de pixels là où il faut lire un libellé mal aligné.
    ///
    /// Sans ce plancher, une marque large entraînait une zone dilatée de 3500 px ramenée
    /// à 896 : un quart de la taille native, la moitié de la taille logique. Le premier
    /// cadre tracé autour d'un paragraphe est ressorti flou.
    ///
    /// Le contexte cède avant la netteté : quand les deux ne tiennent pas ensemble, on
    /// resserre le cadrage plutôt que d'écraser les pixels.
    static let minScale: CGFloat = 0.5

    enum Kind: String, Sendable {
        case crop, full
    }

    struct Result: Sendable {
        let image: CGImage
        let kind: Kind
        /// Rectangle prélevé dans l'image source, en pixels. Utile au rapport : il permet
        /// de resituer un recadrage dans la capture entière sans la recharger.
        let sourceRect: CGRect
        /// Facteurs appliqués entre `sourceRect` et `image`, un par axe.
        ///
        /// Deux facteurs et non un seul : les dimensions finales sont des multiples de 28
        /// et le prélèvement des entiers de pixels, deux contraintes qui ne peuvent pas
        /// tomber juste en même temps. L'écart résiduel est infime — moins de 1 % — mais
        /// un facteur unique le reporte entièrement sur un axe, et le graveur pose alors
        /// la forme à côté.
        ///
        /// Renvoyés par le recadreur plutôt que déduits après coup par l'appelant : la
        /// version précédente les déduisait d'un rapport de largeurs qui mélangeait la
        /// réduction et le rognage d'alignement, et sur un recadrage plus haut que large
        /// le graveur recevait un facteur faux — jusqu'à 18 % d'erreur sur la longueur du
        /// trait. Seul le recadreur sait ce qu'il a fait ; c'est donc à lui de le dire.
        let scaleX: CGFloat
        let scaleY: CGFloat
    }

    /// Recadre autour d'une boîte normalisée.
    ///
    /// `norm` est exprimée dans le repère de l'écran, origine en BAS à gauche comme
    /// partout dans le modèle (§ 3.4) ; `CGImage` a la sienne en HAUT à gauche. Le
    /// retournement se fait ici, une fois, plutôt que dans chaque appelant — c'est
    /// exactement le genre d'inversion qui produit un recadrage juste en haut de l'écran
    /// et faux en bas, donc juste la moitié du temps.
    static func crop(_ image: CGImage, around norm: NormRect) -> Result {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let full = CGRect(x: 0, y: 0, width: w, height: h)

        let box = CGRect(x: CGFloat(norm.x) * w,
                         y: (1 - CGFloat(norm.y) - CGFloat(norm.h)) * h,
                         width: CGFloat(norm.w) * w,
                         height: CGFloat(norm.h) * h)

        let dilated = dilate(box, in: full)

        // Le seuil des 40 % porte sur la boîte DILATÉE, avant que le côté long ne soit
        // borné — et l'ordre n'est pas un détail.
        //
        // Testé dans l'autre sens, la bascule sur `full` devient inatteignable : le
        // bornage ramène tout recadrage à 896 px de côté long au plus, soit 0,8 Mpx,
        // qui n'atteint jamais 40 % d'une capture de 7,7 Mpx. La règle existait sans
        // jamais s'appliquer. Posée sur la boîte dilatée, elle dit ce qu'elle doit
        // dire : quand ce qu'on désigne occupe déjà une grande part de l'écran,
        // recadrer ne retire aucun bruit et fait juste perdre le reste du contexte.
        guard dilated.width * dilated.height < full.width * full.height * fullThreshold
        else { return Result(image: image, kind: .full, sourceRect: full,
                             scaleX: 1, scaleY: 1) }

        // Le prélèvement contient TOUJOURS la boîte dilatée. Il n'est agrandi que par
        // le bas — pour montrer du contexte quand la marque est minuscule — et jamais
        // rogné par le haut.
        //
        // Rogner un prélèvement trop grand pour tenir dans 896 px l'a coupé au milieu de
        // la marque : un surlignage de 1037 px natifs se retrouvait dans un recadrage de
        // 896 px, dont il débordait des deux côtés. La borne haute ne concerne pas la
        // ZONE prélevée mais l'image FINALE, et c'est la réduction qui l'y amène.
        let tightened = tighten(dilated, around: box, in: full)
        let rect = align(growToMinimum(tightened, in: full), in: full)
        return finish(image, prelevement: rect, in: full)
    }

    /// Resserre un prélèvement trop large pour rester net, sans jamais couper la marque.
    ///
    /// L'ordre des priorités est ici : la marque entière d'abord, la netteté ensuite, le
    /// contexte en dernier. Une marque plus large que ce que le plancher autorise force
    /// donc une réduction plus forte — mieux vaut un sujet flou qu'un sujet tronqué.
    static func tighten(_ dilated: CGRect, around box: CGRect, in bounds: CGRect) -> CGRect {
        let maxSpan = longSideRange.upperBound / minScale
        let long = max(dilated.width, dilated.height)
        guard long > maxSpan else { return dilated }

        // La marque, plus une marge d'un huitième de part et d'autre : sans elle, le
        // cadre toucherait le bord de l'image et l'on ne verrait plus ce qu'il entoure.
        let needed = max(box.width, box.height) * 1.25
        let target = max(min(long, maxSpan), needed)
        let factor = target / long

        let w = dilated.width * factor, h = dilated.height * factor
        return CGRect(x: dilated.midX - w / 2, y: dilated.midY - h / 2, width: w, height: h)
            .intersection(bounds)
    }

    // MARK: - Étapes

    /// Taille en deçà de laquelle on préfère décentrer plutôt que rétrécir encore.
    static let centeringFloor: CGFloat = 280

    /// Dilate autour du centre, sans sortir de l'image, en gardant le sujet AU MILIEU.
    ///
    /// Quand la boîte dilatée déborde, la réduire symétriquement plutôt que couper le
    /// débordement d'un seul côté. Couper conserve la taille mais déplace le centre :
    /// l'élément désigné se retrouve alors décalé dans l'image, ce qui va exactement
    /// contre la raison d'être du recadrage.
    ///
    /// En deçà de `centeringFloor`, le compromis s'inverse : un sujet à vingt pixels d'un
    /// bord donnerait un recadrage de quarante pixels, illisible. On accepte alors de le
    /// décentrer pour garder une image exploitable.
    static func dilate(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let cx = box.midX, cy = box.midY
        var w = max(box.width * dilation, 1), h = max(box.height * dilation, 1)

        let roomX = 2 * min(cx - bounds.minX, bounds.maxX - cx)
        let roomY = 2 * min(cy - bounds.minY, bounds.maxY - cy)
        if roomX >= centeringFloor { w = min(w, roomX) }
        if roomY >= centeringFloor { h = min(h, roomY) }

        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            .intersection(bounds)
    }

    /// Agrandit un prélèvement trop petit pour être exploitable.
    ///
    /// Uniquement vers le haut : un recadrage de 80 px ne montre rien de son
    /// environnement, alors qu'un recadrage trop grand se corrige sans perte par la
    /// réduction. Le recentrage est REPOUSSÉ dans l'image quand il déborde, plutôt que
    /// rogné : rogner décentrerait la marque, qui est le sujet.
    static func growToMinimum(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let long = max(box.width, box.height)
        guard long > 0, long < longSideRange.lowerBound else { return box }

        let factor = longSideRange.lowerBound / long
        let w = min(box.width * factor, bounds.width)
        let h = min(box.height * factor, bounds.height)

        var rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        rect.origin.x = min(max(rect.origin.x, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), bounds.maxY - rect.height)
        return rect
    }

    /// Aligne les dimensions sur des multiples de la tuile de facturation.
    ///
    /// On arrondit vers le HAUT quand la place existe : une tuile entamée est facturée
    /// entière, autant qu'elle porte des pixels utiles plutôt que du vide.
    static func align(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let t = CGFloat(tile)
        var w = (box.width / t).rounded(.up) * t
        var h = (box.height / t).rounded(.up) * t
        if w > bounds.width { w = (bounds.width / t).rounded(.down) * t }
        if h > bounds.height { h = (bounds.height / t).rounded(.down) * t }
        w = max(w, t); h = max(h, t)

        var rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        rect.origin.x = (min(max(rect.origin.x, bounds.minX), bounds.maxX - w)).rounded()
        rect.origin.y = (min(max(rect.origin.y, bounds.minY), bounds.maxY - h)).rounded()
        return rect
    }

    // MARK: - Réduction

    /// Contexte partagé. Le recréer par appel coûte des dizaines de millisecondes de
    /// compilation de noyaux, à chaque marque.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Réduit une image par transformation de Lanczos.
    ///
    /// `CILanczosScaleTransform` et jamais un simple redessin dans un contexte plus
    /// petit : ce dernier interpole linéairement, et l'interpolation linéaire est
    /// précisément ce qui efface un liseré d'un pixel — soit le défaut d'alignement que
    /// la marque désignait.
    static func scale(_ image: CGImage, toLongSide target: CGFloat) -> CGImage {
        let long = CGFloat(max(image.width, image.height))
        guard long > target, target > 0 else { return image }

        let factor = target / long
        let filter = CIFilter(name: "CILanczosScaleTransform")
        filter?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter?.setValue(factor, forKey: kCIInputScaleKey)
        filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = filter?.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent)
        else { return image }
        return result
    }

    /// Prélève et réduit, en gardant la transformation exacte.
    ///
    /// L'ordre est ce qui compte : les dimensions finales sont décidées d'abord, puis le
    /// prélèvement est ajusté pour avoir EXACTEMENT leur rapport, et seulement ensuite
    /// réduit. La réduction est alors un facteur pur, identique sur les deux axes, que
    /// l'on peut transmettre au graveur sans approximation.
    ///
    /// L'ordre inverse — réduire puis rogner à la tuile — était plus simple à écrire et
    /// faux : le rognage déplace l'origine et modifie le rapport, deux effets que le
    /// facteur ne porte pas.
    static func finish(_ image: CGImage, prelevement: CGRect, in bounds: CGRect) -> Result {
        let t = CGFloat(tile)
        let long = max(prelevement.width, prelevement.height)

        // Deux freins, et l'on retient le plus serré :
        //
        //   le côté long, pour qu'une image ne devienne pas absurdement grande ;
        //   la SURFACE en tuiles, qui est ce que le modèle facture réellement.
        //
        // Jamais d'agrandissement : Lanczos rendrait un flou propre, mais un flou quand
        // même, et le détail annoté est ce qui compte.
        let bySide = longSideRange.upperBound / long
        let area = prelevement.width * prelevement.height
        let byBudget = (cropTileBudget * t * t / max(area, 1)).squareRoot()
        let factor = min(1, min(bySide, byBudget))

        // Dimensions finales, multiples de la tuile de facturation.
        var outW = ((prelevement.width * factor) / t).rounded(.down) * t
        var outH = ((prelevement.height * factor) / t).rounded(.down) * t
        outW = max(outW, t)
        outH = max(outH, t)

        // Le prélèvement est ramené au rapport EXACT des dimensions finales, par un
        // rognage centré. Il reste centré sur ce que la marque désigne, et perd au plus
        // une tuile sur chaque axe.
        var rect = CGRect(x: prelevement.midX - outW / factor / 2,
                          y: prelevement.midY - outH / factor / 2,
                          width: outW / factor, height: outH / factor)
        rect.origin.x = min(max(rect.origin.x, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), bounds.maxY - rect.height)
        rect = rect.integral

        guard rect.width >= 1, rect.height >= 1,
              let cropped = image.cropping(to: rect) else {
            return Result(image: image, kind: .full, sourceRect: bounds,
                          scaleX: 1, scaleY: 1)
        }

        let final = scaleExact(cropped, to: CGSize(width: outW, height: outH))
        return Result(image: final, kind: .crop, sourceRect: rect,
                      scaleX: CGFloat(final.width) / rect.width,
                      scaleY: CGFloat(final.height) / rect.height)
    }

    /// Réduit à des dimensions exactes. Le rapport d'aspect de l'entrée doit déjà être
    /// celui de la sortie ; `CILanczosScaleTransform` corrige le reliquat d'arrondi.
    static func scaleExact(_ image: CGImage, to size: CGSize) -> CGImage {
        guard size.width >= 1, size.height >= 1,
              CGFloat(image.width) != size.width || CGFloat(image.height) != size.height
        else { return image }

        let filter = CIFilter(name: "CILanczosScaleTransform")
        filter?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter?.setValue(size.height / CGFloat(image.height), forKey: kCIInputScaleKey)
        filter?.setValue((size.width / size.height)
                         / (CGFloat(image.width) / CGFloat(image.height)),
                         forKey: kCIInputAspectRatioKey)

        guard let output = filter?.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent)
        else { return image }
        return result
    }

    /// Dimensions cibles d'un palier de facturation — § 9.2.
    ///
    /// `hp = floor(sqrt(B/r))`, `wp = min(92, floor(hp·r))`, cible `28·wp × 28·hp`.
    /// Le plafond de 92 tuiles existe parce qu'au-delà le modèle redimensionne lui-même :
    /// envoyer plus large ne fait que payer un transfert pour un détail qui sera jeté.
    static func tileTarget(width: Int, height: Int, budget: Double) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let r = Double(width) / Double(height)
        let hp = max(1, Int((budget / r).squareRoot().rounded(.down)))
        let wp = max(1, min(92, Int((Double(hp) * r).rounded(.down))))
        return CGSize(width: wp * tile, height: hp * tile)
    }
}
